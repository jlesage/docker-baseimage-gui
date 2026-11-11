#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <nestegg/nestegg.h>
#include <opus/opus.h>

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error PulseAudio source format is s16le
#endif

namespace {

constexpr char kSocketPath[] = "/tmp/vnc-microphone.sock";
constexpr char kFifoPath[] = "/tmp/vnc-microphone.fifo";

constexpr int kRate = 48000;
constexpr int kPipeBytes = 4096;
// PulseAudio does not read the FIFO until an application is recording. Keep
// the same 200 ms bound as the original pipeline queue and drop older samples,
// so that wait is not played later as a late gulp.
constexpr size_t kQueueSamples = static_cast<size_t>(kRate) * 200 / 1000;
constexpr size_t kQueueBytes = kQueueSamples * sizeof(int16_t);
// nestegg rewinds to a position it already parsed. Once the header has been
// read, bytes older than this window are not needed.
constexpr size_t kRewindBytes = 256 * 1024;
constexpr int kOpusMaxSamples = 5760;

std::atomic<bool> g_stop{false};
std::atomic<bool> g_fatal{false};

void log_msg(const char* message) {
    std::fprintf(stderr, "%s\n", message);
}

void on_signal(int) {
    g_stop.store(true);
}

uint32_t samples_from_ns(uint64_t ns) {
    return static_cast<uint32_t>((ns * static_cast<uint64_t>(kRate)) / 1000000000ULL);
}

// One thread decodes and writes. While waiting for the next client bytes it
// also polls the FIFO, so a pipe PulseAudio is not reading cannot stall decode.
// The one-second gulp was nestegg blocking until an 8 KB read was full.
class PipeOutput {
public:
    void set_fd(int fd) { fd_ = fd; }

    void reset() { pending_.clear(); }

    void write(const int16_t* pcm, size_t count) {
        if (g_fatal.load() || count == 0 || fd_ < 0) {
            return;
        }
        const auto* bytes = reinterpret_cast<const uint8_t*>(pcm);
        pending_.insert(pending_.end(), bytes, bytes + count * sizeof(int16_t));
        if (pending_.size() > kQueueBytes) {
            size_t drop = pending_.size() - kQueueBytes;
            drop -= drop % sizeof(int16_t);
            pending_.erase(pending_.begin(), pending_.begin() + static_cast<std::ptrdiff_t>(drop));
        }
        flush();
    }

    // The last samples are still the end of the recording. Wait out the queue
    // bound, then drop anything the recorder did not take.
    void drain() {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
        while (!pending_.empty() && !g_stop.load() && !g_fatal.load()) {
            if (flush()) {
                return;
            }
            const auto left = deadline - std::chrono::steady_clock::now();
            if (left <= std::chrono::steady_clock::duration::zero()) {
                pending_.clear();
                return;
            }
            const int timeout = static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(left).count());
            pollfd pfd{};
            pfd.fd = fd_;
            pfd.events = POLLOUT;
            ::poll(&pfd, 1, timeout);
        }
    }

    // True when fd has bytes to read. A full FIFO is written in between.
    bool wait_readable(int fd) {
        while (!g_stop.load() && !g_fatal.load()) {
            flush();
            pollfd pfds[2]{};
            pfds[0].fd = fd;
            pfds[0].events = POLLIN;
            nfds_t nfds = 1;
            if (!pending_.empty()) {
                pfds[1].fd = fd_;
                pfds[1].events = POLLOUT;
                nfds = 2;
            }
            const int pr = ::poll(pfds, nfds, 200);
            if (pr < 0) {
                if (errno == EINTR) {
                    continue;
                }
                return false;
            }
            if (pr == 0) {
                continue;
            }
            if (nfds == 2 && (pfds[1].revents & (POLLERR | POLLHUP | POLLNVAL))) {
                log_msg("capture fifo closed");
                g_fatal.store(true);
                g_stop.store(true);
                return false;
            }
            if (pfds[0].revents & (POLLERR | POLLNVAL)) {
                return false;
            }
            if (pfds[0].revents & (POLLIN | POLLHUP)) {
                return true;
            }
        }
        return false;
    }

private:
    // True when nothing is left waiting. False when the pipe cannot take more.
    bool flush() {
        while (!pending_.empty()) {
            const ssize_t n = ::write(fd_, pending_.data(), pending_.size());
            if (n > 0) {
                pending_.erase(pending_.begin(), pending_.begin() + n);
                continue;
            }
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                return false;
            }
            if (!g_stop.load()) {
                log_msg("capture fifo closed");
                g_fatal.store(true);
                g_stop.store(true);
            }
            return false;
        }
        return true;
    }

    int fd_ = -1;
    std::vector<uint8_t> pending_;
};

PipeOutput g_output;

struct ByteStream {
    int fd = -1;
    std::vector<uint8_t> data;
    uint64_t base = 0;
    uint64_t pos = 0;
    bool eof = false;
    bool allow_trim = false;

    bool pull() {
        while (!g_stop.load()) {
            if (!g_output.wait_readable(fd)) {
                return false;
            }
            uint8_t tmp[4096];
            const ssize_t n = ::recv(fd, tmp, sizeof(tmp), 0);
            if (n > 0) {
                data.insert(data.end(), tmp, tmp + n);
                return true;
            }
            if (n == 0) {
                eof = true;
                return true;
            }
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            return false;
        }
        return false;
    }

    void trim() {
        if (!allow_trim || pos < base + kRewindBytes) {
            return;
        }
        const uint64_t drop_to = pos - kRewindBytes;
        const size_t drop = static_cast<size_t>(drop_to - base);
        if (drop > data.size()) {
            return;
        }
        data.erase(data.begin(), data.begin() + static_cast<std::ptrdiff_t>(drop));
        base = drop_to;
    }
};

int64_t stream_read(void* buffer, size_t length, void* userdata) {
    auto* stream = static_cast<ByteStream*>(userdata);
    auto* out = static_cast<uint8_t*>(buffer);
    size_t filled = 0;

    while (filled < length) {
        if (stream->pos < stream->base) {
            return -1;
        }
        const uint64_t end = stream->base + stream->data.size();
        if (stream->pos < end) {
            const size_t index = static_cast<size_t>(stream->pos - stream->base);
            const size_t n = std::min(length - filled, stream->data.size() - index);
            std::memcpy(out + filled, stream->data.data() + index, n);
            stream->pos += n;
            filled += n;
            continue;
        }
        // nestegg asks for up to 8 KB. Waiting until that is full holds a
        // second of WebM, then every block in it is decoded at once and the
        // pipe gets a one-second gulp. A short read is parsed immediately.
        if (filled > 0 || stream->eof) {
            break;
        }
        if (!stream->pull()) {
            return -1;
        }
    }
    stream->trim();
    return static_cast<int64_t>(filled);
}

int stream_seek(int64_t offset, int whence, void* userdata) {
    if (whence != NESTEGG_SEEK_SET || offset < 0) {
        return -1;
    }
    auto* stream = static_cast<ByteStream*>(userdata);
    if (static_cast<uint64_t>(offset) < stream->base) {
        return -1;
    }
    while (static_cast<uint64_t>(offset) > stream->base + stream->data.size()) {
        if (stream->eof) {
            return -1;
        }
        if (!stream->pull()) {
            return -1;
        }
    }
    stream->pos = static_cast<uint64_t>(offset);
    return 0;
}

int64_t stream_tell(void* userdata) {
    return static_cast<int64_t>(static_cast<ByteStream*>(userdata)->pos);
}

bool opus_head(const unsigned char* data, size_t length, int* channels, uint32_t* preskip) {
    if (length < 19 || std::memcmp(data, "OpusHead", 8) != 0 || data[8] != 1) {
        return false;
    }
    *channels = data[9];
    *preskip = static_cast<uint32_t>(data[10] | (data[11] << 8));
    return *channels == 1 || *channels == 2;
}

void emit_pcm(const opus_int16* pcm, int samples, int channels, uint32_t* preskip) {
    if (samples <= 0) {
        return;
    }
    std::vector<int16_t> mono(static_cast<size_t>(samples));
    for (int i = 0; i < samples; i++) {
        int sum = 0;
        for (int c = 0; c < channels; c++) {
            sum += pcm[i * channels + c];
        }
        mono[static_cast<size_t>(i)] = static_cast<int16_t>(sum / channels);
    }

    size_t start = 0;
    if (*preskip > 0) {
        const size_t skip = std::min(static_cast<size_t>(*preskip), mono.size());
        *preskip -= static_cast<uint32_t>(skip);
        start = skip;
    }
    if (start < mono.size()) {
        const size_t count = mono.size() - start;
        g_output.write(mono.data() + start, count);
    }
}

bool read_exact(int fd, void* buffer, size_t length) {
    auto* out = static_cast<uint8_t*>(buffer);
    while (length > 0) {
        if (g_stop.load()) {
            return false;
        }
        const ssize_t n = ::recv(fd, out, length, 0);
        if (n > 0) {
            out += n;
            length -= static_cast<size_t>(n);
            continue;
        }
        if (n == 0) {
            return false;
        }
        if (errno == EINTR) {
            continue;
        }
        return false;
    }
    return true;
}

// Raw frames have no container delay. PCM1 is followed by the sample rate
// and then little-endian mono samples at that rate.
bool pcm_client(int fd) {
    uint8_t rate_bytes[4];
    if (!read_exact(fd, rate_bytes, sizeof(rate_bytes))) {
        return false;
    }
    const uint32_t rate = static_cast<uint32_t>(rate_bytes[0] | (rate_bytes[1] << 8) |
                                                (rate_bytes[2] << 16) | (rate_bytes[3] << 24));
    if (rate != static_cast<uint32_t>(kRate)) {
        log_msg("PCM sample rate rejected");
        return false;
    }

    std::vector<uint8_t> pending;
    uint8_t tmp[4096];
    while (!g_stop.load()) {
        if (!g_output.wait_readable(fd)) {
            return !g_fatal.load();
        }
        const ssize_t n = ::recv(fd, tmp, sizeof(tmp), 0);
        if (n == 0) {
            return true;
        }
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        pending.insert(pending.end(), tmp, tmp + n);
        const size_t samples = pending.size() / sizeof(int16_t);
        if (samples == 0) {
            continue;
        }
        const size_t bytes = samples * sizeof(int16_t);
        g_output.write(reinterpret_cast<const int16_t*>(pending.data()), samples);
        pending.erase(pending.begin(), pending.begin() + static_cast<std::ptrdiff_t>(bytes));
    }
    return true;
}

bool decode_client(int fd, const uint8_t* prefix, size_t prefix_len) {
    ByteStream stream;
    stream.fd = fd;
    if (prefix_len > 0) {
        stream.data.assign(prefix, prefix + prefix_len);
    }

    nestegg_io io{};
    io.read = stream_read;
    io.seek = stream_seek;
    io.tell = stream_tell;
    io.userdata = &stream;

    nestegg* ctx = nullptr;
    if (nestegg_init(&ctx, io, nullptr, -1) != 0) {
        log_msg("WebM header rejected");
        return false;
    }
    stream.allow_trim = true;

    unsigned int tracks = 0;
    if (nestegg_track_count(ctx, &tracks) != 0) {
        nestegg_destroy(ctx);
        log_msg("WebM has no tracks");
        return false;
    }

    int track = -1;
    for (unsigned int i = 0; i < tracks; i++) {
        if (nestegg_track_type(ctx, i) == NESTEGG_TRACK_AUDIO &&
            nestegg_track_codec_id(ctx, i) == NESTEGG_CODEC_OPUS) {
            track = static_cast<int>(i);
            break;
        }
    }
    if (track < 0) {
        nestegg_destroy(ctx);
        log_msg("WebM has no Opus track");
        return false;
    }

    int channels = 0;
    uint32_t preskip = 0;
    unsigned int headers = 0;
    unsigned char* header = nullptr;
    size_t header_len = 0;
    if (nestegg_track_codec_data_count(ctx, static_cast<unsigned int>(track), &headers) == 0 &&
        headers > 0 &&
        nestegg_track_codec_data(ctx, static_cast<unsigned int>(track), 0, &header, &header_len) == 0 &&
        opus_head(header, header_len, &channels, &preskip)) {
        // OpusHead pre-skip is encoder delay, not microphone audio.
    } else {
        nestegg_audio_params params{};
        if (nestegg_track_audio_params(ctx, static_cast<unsigned int>(track), &params) != 0 ||
            (params.channels != 1 && params.channels != 2)) {
            nestegg_destroy(ctx);
            log_msg("Opus track parameters rejected");
            return false;
        }
        channels = static_cast<int>(params.channels);
        preskip = samples_from_ns(params.codec_delay);
    }

    int opus_err = 0;
    OpusDecoder* decoder = opus_decoder_create(kRate, channels, &opus_err);
    if (decoder == nullptr) {
        nestegg_destroy(ctx);
        log_msg("Opus decoder creation failed");
        return false;
    }

    int decode_errors = 0;
    nestegg_packet* packet = nullptr;
    int read_result = 0;
    while (!g_stop.load() && ((read_result = nestegg_read_packet(ctx, &packet)) > 0)) {
        unsigned int packet_track = 0;
        if (nestegg_packet_track(packet, &packet_track) != 0 ||
            static_cast<int>(packet_track) != track) {
            nestegg_free_packet(packet);
            continue;
        }

        unsigned int chunks = 0;
        if (nestegg_packet_count(packet, &chunks) != 0) {
            nestegg_free_packet(packet);
            continue;
        }

        int64_t discard_ns = 0;
        if (nestegg_packet_discard_padding(packet, &discard_ns) != 0) {
            discard_ns = 0;
        }

        for (unsigned int chunk = 0; chunk < chunks; chunk++) {
            unsigned char* payload = nullptr;
            size_t payload_len = 0;
            if (nestegg_packet_data(packet, chunk, &payload, &payload_len) != 0 || payload_len == 0) {
                continue;
            }

            opus_int16 pcm[kOpusMaxSamples * 2];
            const int samples = opus_decode(decoder, payload, static_cast<opus_int32>(payload_len),
                                            pcm, kOpusMaxSamples, 0);
            if (samples < 0) {
                if (decode_errors++ == 0) {
                    log_msg("Opus packet rejected");
                }
                continue;
            }

            int usable = samples;
            if (chunk + 1 == chunks && discard_ns > 0) {
                const int discard = static_cast<int>(samples_from_ns(static_cast<uint64_t>(discard_ns)));
                if (discard >= usable) {
                    continue;
                }
                usable -= discard;
            }
            emit_pcm(pcm, usable, channels, &preskip);
        }
        nestegg_free_packet(packet);
        packet = nullptr;
    }

    if (decode_errors > 1) {
        std::fprintf(stderr, "%d Opus packets rejected\n", decode_errors);
    }
    opus_decoder_destroy(decoder);
    nestegg_destroy(ctx);
    return read_result >= 0;
}

int open_fifo() {
    for (int attempt = 0; attempt < 100 && !g_stop.load(); attempt++) {
        const int fd = ::open(kFifoPath, O_WRONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0) {
            if (::fcntl(fd, F_SETPIPE_SZ, kPipeBytes) < 0) {
                log_msg("could not limit capture fifo capacity");
            }
            return fd;
        }
        if (errno != ENOENT && errno != ENXIO) {
            std::fprintf(stderr, "open %s: %s\n", kFifoPath, std::strerror(errno));
            return -1;
        }
        ::poll(nullptr, 0, 100);
    }
    log_msg("capture fifo did not appear");
    return -1;
}

int listen_socket() {
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        log_msg("socket failed");
        return -1;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", kSocketPath);
    ::unlink(kSocketPath);
    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::fprintf(stderr, "bind %s: %s\n", kSocketPath, std::strerror(errno));
        ::close(fd);
        return -1;
    }
    if (::chmod(kSocketPath, 0600) < 0 || ::listen(fd, 1) < 0) {
        log_msg("listen failed");
        ::close(fd);
        ::unlink(kSocketPath);
        return -1;
    }
    return fd;
}

}  // namespace

int main() {
    struct sigaction action{};
    action.sa_handler = on_signal;
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    action.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &action, nullptr);

    const int fifo = open_fifo();
    if (fifo < 0) {
        return 1;
    }
    g_output.set_fd(fifo);

    const int server = listen_socket();
    if (server < 0) {
        g_stop.store(true);
        ::close(fifo);
        return 1;
    }
    while (!g_stop.load()) {
        pollfd pfd{};
        pfd.fd = server;
        pfd.events = POLLIN;
        const int pr = ::poll(&pfd, 1, 200);
        if (pr < 0) {
            if (errno == EINTR) {
                continue;
            }
            g_fatal.store(true);
            break;
        }
        if (pr == 0 || !(pfd.revents & POLLIN)) {
            continue;
        }

        const int client = ::accept(server, nullptr, nullptr);
        if (client < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            g_fatal.store(true);
            break;
        }
        ::fcntl(client, F_SETFD, FD_CLOEXEC);
        // Samples still waiting from the previous client are not part of this one.
        g_output.reset();
        uint8_t magic[4] = {};
        if (read_exact(client, magic, sizeof(magic))) {
            if (std::memcmp(magic, "PCM1", 4) == 0) {
                pcm_client(client);
            } else {
                decode_client(client, magic, sizeof(magic));
            }
        }
        g_output.drain();
        ::close(client);
    }

    g_stop.store(true);
    ::close(server);
    ::close(fifo);
    ::unlink(kSocketPath);
    return g_fatal.load() ? 1 : 0;
}
