/*
 * Receive WebM/Opus over a Unix socket, demux it with nestegg, decode it with
 * libopus, and write 48 kHz mono s16le PCM to PulseAudio's pipe-source FIFO.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glib-unix.h>
#include <nestegg/nestegg.h>
#include <opus.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

/*
 * -------------------------------------------------------------------------
 * Configuration and state
 * -------------------------------------------------------------------------
 */

enum {
    FIFO_BUFFER_BYTES = 4096,
    INPUT_TIMEOUT_MS = 10000,
    OUTPUT_TIMEOUT_MS = 1000,
    CANCEL_CHECK_MS = 50,
    SAMPLE_RATE = 48000,
    NANOSECONDS_PER_SECOND = 1000000000,
    MAX_PACKET_SAMPLES = SAMPLE_RATE,  // Limit decoded laced blocks to one second.
    MAX_OPUS_BYTES = 65536,            // Limit decoder input, not nestegg allocations.
    MAX_HEADER_BYTES = 256 * 1024,     // Limit header parsing in nestegg_init().
    INPUT_REPLAY_BYTES = 8192,  // Match IO_BUFFER_SIZE in the nestegg revision pinned by build.sh.
};

struct microphone_bridge {
    GMainLoop* loop;

    GThread* worker;
    guint client_watch;
    int client_fd;
    int fifo_fd;
    gint stop_requested;
    gint worker_finished;

    const char* fifo_path;
};

// The decoding worker owns this state for the duration of one recording.
struct recording_state {
    struct microphone_bridge* bridge;
    int64_t read_offset;
    int64_t received_bytes;
    unsigned char replay_buffer[INPUT_REPLAY_BYTES];
    int64_t last_input_time;
    unsigned int pre_skip_remaining;
    OpusDecoder* decoder;
};

/*
 * -------------------------------------------------------------------------
 * PulseAudio FIFO output
 * -------------------------------------------------------------------------
 */

static bool is_owned_fifo(const struct stat* info)
{ return S_ISFIFO(info->st_mode) && info->st_uid == getuid(); }

/*
 * Decoding and FIFO output share one worker. If output stalls, the
 * recording ends instead of accumulating audio in a separate queue.
 */
static bool write_pcm_to_fifo(struct microphone_bridge* bridge, opus_int16* pcm, size_t count)
{
    for (size_t i = 0; i < count; ++i) { pcm[i] = (opus_int16)GUINT16_TO_LE((guint16)pcm[i]); }

    int64_t deadline = g_get_monotonic_time() + (int64_t)OUTPUT_TIMEOUT_MS * 1000;

    while (count > 0 && !g_atomic_int_get(&bridge->stop_requested)) {
        int64_t remaining = (deadline - g_get_monotonic_time()) / 1000;
        if (remaining <= 0) {
            g_warning("microphone FIFO output stalled for %d ms (check PulseAudio)",
                      OUTPUT_TIMEOUT_MS);
            return false;
        }

        size_t bytes = MIN(count * sizeof(*pcm), FIFO_BUFFER_BYTES);
        ssize_t written = write(bridge->fifo_fd, pcm, bytes);
        if (written < 0 && errno == EINTR) { continue; }
        if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd output = {.fd = bridge->fifo_fd, .events = POLLOUT};
            if (poll(&output, 1, (int)MIN(remaining, CANCEL_CHECK_MS)) < 0 && errno != EINTR) {
                g_warning("cannot wait for microphone FIFO output: %s", strerror(errno));
                return false;
            }
            continue;
        }

        if (written <= 0 || written % sizeof(*pcm) != 0) {
            g_warning("cannot write microphone PCM to FIFO: %s (check PulseAudio)",
                      written < 0 ? strerror(errno) : "incomplete sample write");
            return false;
        }

        size_t samples_written = (size_t)written / sizeof(*pcm);
        pcm += samples_written;
        count -= samples_written;
    }

    return !g_atomic_int_get(&bridge->stop_requested);
}

/*
 * Open and validate the PulseAudio pipe-source FIFO. On failure, the
 * caller releases any open descriptor through close_client().
 */
static bool open_fifo(struct microphone_bridge* bridge)
{
    bridge->fifo_fd = open(bridge->fifo_path, O_WRONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (bridge->fifo_fd < 0) {
        g_warning("cannot open microphone FIFO '%s': %s", bridge->fifo_path, strerror(errno));
        return false;
    }

    struct stat fifo_info;
    if (fstat(bridge->fifo_fd, &fifo_info) < 0) {
        g_warning("cannot inspect opened microphone FIFO: %s", strerror(errno));
        return false;
    }
    if (!is_owned_fifo(&fifo_info)) {
        g_warning("microphone path must be a FIFO owned by this user: %s", bridge->fifo_path);
        return false;
    }

    // Limit kernel buffering to avoid accumulating stale audio during a stall.
    if (fcntl(bridge->fifo_fd, F_SETPIPE_SZ, FIFO_BUFFER_BYTES) < 0) {
        g_warning("could not reduce microphone FIFO capacity: %s", strerror(errno));
    }

    return true;
}

/*
 * -------------------------------------------------------------------------
 * WebM stream input
 * -------------------------------------------------------------------------
 */

/*
 * nestegg reads from the non-seekable socket on the recording worker,
 * leaving the GLib listener and signal handlers responsive.
 */
static int64_t read_webm_stream(void* buffer, size_t length, void* userdata)
{
    struct recording_state* recording = userdata;
    struct microphone_bridge* bridge = recording->bridge;
    /*
     * Keep nestegg's read-ahead window for backward seeks without
     * buffering the entire recording.
     */
    if (recording->read_offset < recording->received_bytes) {
        size_t count = MIN(length, (size_t)(recording->received_bytes - recording->read_offset));
        size_t index = (size_t)(recording->read_offset % INPUT_REPLAY_BYTES);
        size_t first = MIN(count, INPUT_REPLAY_BYTES - index);
        memcpy(buffer, recording->replay_buffer + index, first);
        memcpy((unsigned char*)buffer + first, recording->replay_buffer, count - first);
        recording->read_offset += (int64_t)count;
        return (int64_t)count;
    }

    while (!g_atomic_int_get(&bridge->stop_requested)) {
        ssize_t count =
            recv(bridge->client_fd, buffer, MIN(length, INPUT_REPLAY_BYTES), MSG_DONTWAIT);
        if (count >= 0) {
            size_t index = (size_t)(recording->read_offset % INPUT_REPLAY_BYTES);
            size_t first = MIN((size_t)count, INPUT_REPLAY_BYTES - index);
            memcpy(recording->replay_buffer + index, buffer, first);
            memcpy(recording->replay_buffer, (unsigned char*)buffer + first, (size_t)count - first);
            recording->read_offset += count;
            recording->received_bytes += count;
            if (count > 0) { recording->last_input_time = g_get_monotonic_time(); }
            return count;
        }

        if (errno == EINTR) { continue; }
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            if (!g_atomic_int_get(&bridge->stop_requested)) {
                g_warning("cannot read microphone stream: %s", strerror(errno));
            }
            return -1;
        }

        int64_t remaining =
            INPUT_TIMEOUT_MS - (g_get_monotonic_time() - recording->last_input_time) / 1000;
        if (remaining <= 0) {
            g_warning("microphone sender supplied no data for 10 seconds");
            return -1;
        }

        struct pollfd input = {.fd = bridge->client_fd, .events = POLLIN};
        if (poll(&input, 1, (int)remaining) < 0 && errno != EINTR) {
            g_warning("cannot wait for microphone input: %s", strerror(errno));
            return -1;
        }
    }

    return -1;
}

static int seek_webm_stream(int64_t offset, int whence, void* userdata)
{
    struct recording_state* recording = userdata;

    if (whence != NESTEGG_SEEK_SET || offset < 0 || offset > recording->received_bytes ||
        offset < recording->received_bytes - INPUT_REPLAY_BYTES) {
        g_warning("unsupported seek in microphone WebM stream");
        return -1;
    }

    recording->read_offset = offset;
    return 0;
}

static int64_t tell_webm_stream(void* userdata)
{ return ((struct recording_state*)userdata)->read_offset; }

/*
 * -------------------------------------------------------------------------
 * Opus decoding
 * -------------------------------------------------------------------------
 */

static unsigned int read_little_endian_u16(const unsigned char* bytes)
{ return bytes[0] | ((unsigned int)bytes[1] << 8); }

// Round durations of at most one second to the nearest sample.
static size_t nanoseconds_to_samples(uint64_t duration)
{ return (size_t)((duration * SAMPLE_RATE + NANOSECONDS_PER_SECOND / 2) / NANOSECONDS_PER_SECOND); }

static bool configure_decoder(struct recording_state* recording, nestegg* demux)
{
    unsigned int tracks;
    if (nestegg_track_count(demux, &tracks) != 0 || tracks != 1 ||
        nestegg_track_type(demux, 0) != NESTEGG_TRACK_AUDIO ||
        nestegg_track_codec_id(demux, 0) != NESTEGG_CODEC_OPUS) {
        g_warning("microphone stream must contain exactly one WebM/Opus audio track");
        return false;
    }

    nestegg_audio_params params;
    unsigned char* header;
    size_t length;
    if (nestegg_track_audio_params(demux, 0, &params) != 0 ||
        nestegg_track_codec_data(demux, 0, 0, &header, &length) != 0 || length < 19 ||
        memcmp(header, "OpusHead", 8) != 0 || header[8] > 15 ||
        (header[9] != 1 && header[9] != 2) || header[18] != 0 || params.channels != header[9]) {
        g_warning("unsupported WebM/Opus header (requires mono or stereo with mapping family 0)");
        return false;
    }

    // WebM requires CodecDelay to represent the same pre-skip as OpusHead.
    recording->pre_skip_remaining = read_little_endian_u16(header + 10);

    int error;
    recording->decoder = opus_decoder_create(SAMPLE_RATE, 1, &error);
    if (recording->decoder == NULL) {
        g_warning("cannot create microphone decoder: %s", opus_strerror(error));
        return false;
    }

    unsigned int gain = read_little_endian_u16(header + 16);
    int signed_gain = gain < 32768 ? (int)gain : (int)gain - 65536;
    if (opus_decoder_ctl(recording->decoder, OPUS_SET_GAIN(signed_gain)) != OPUS_OK) {
        g_warning("cannot apply microphone Opus output gain");
        return false;
    }

    return true;
}

static bool decode_packet(struct recording_state* recording, nestegg_packet* packet)
{
    unsigned int track, chunks;
    if (nestegg_packet_track(packet, &track) != 0 || track != 0 ||
        nestegg_packet_count(packet, &chunks) != 0 || chunks == 0 || chunks > 256 ||
        nestegg_packet_encryption(packet) != NESTEGG_PACKET_HAS_SIGNAL_BYTE_FALSE) {
        g_warning("unsupported microphone WebM block (invalid track, chunk count, or encryption)");
        return false;
    }

    opus_int16 pcm[MAX_PACKET_SAMPLES];
    size_t samples = 0;
    for (unsigned int i = 0; i < chunks; ++i) {
        unsigned char* encoded;
        size_t length;
        if (nestegg_packet_data(packet, i, &encoded, &length) != 0 || length == 0 ||
            length > MAX_OPUS_BYTES) {
            g_warning("invalid microphone Opus packet length");
            return false;
        }

        if (samples == MAX_PACKET_SAMPLES) {
            g_warning("microphone WebM block exceeds one second of decoded audio");
            return false;
        }

        // libopus validates the packet and respects the remaining PCM capacity.
        int decoded = opus_decode(recording->decoder,
                                  encoded,
                                  (opus_int32)length,
                                  pcm + samples,
                                  (int)(MAX_PACKET_SAMPLES - samples),
                                  0);
        if (decoded < 0) {
            g_warning("cannot decode microphone packet: %s", opus_strerror(decoded));
            return false;
        }

        samples += (size_t)decoded;
    }

    /*
     * DiscardPadding trims one edge of the decoded block, then pre-skip
     * removes any remaining startup samples.
     */
    int64_t padding = 0;
    size_t start = 0, end = samples;
    if (nestegg_packet_discard_padding(packet, &padding) == 0) {
        if (padding < -NANOSECONDS_PER_SECOND || padding > NANOSECONDS_PER_SECOND) {
            g_warning("microphone WebM discard padding exceeds one second");
            return false;
        }

        uint64_t duration = padding < 0 ? (uint64_t)-padding : (uint64_t)padding;
        size_t trim = nanoseconds_to_samples(duration);
        if (trim > samples) {
            g_warning("microphone WebM discard padding exceeds decoded block duration");
            return false;
        }

        if (padding < 0) {
            start = trim;
        } else {
            end -= trim;
        }
    }

    size_t skip = MIN(recording->pre_skip_remaining, end - start);
    recording->pre_skip_remaining -= (unsigned int)skip;
    start += skip;

    return write_pcm_to_fifo(recording->bridge, pcm + start, end - start);
}

/*
 * -------------------------------------------------------------------------
 * Recording worker
 * -------------------------------------------------------------------------
 */

static gpointer receive_recording(gpointer data)
{
    struct microphone_bridge* bridge = data;
    struct recording_state recording = {.bridge = bridge,
                                        .last_input_time = g_get_monotonic_time()};
    nestegg_io io = {.read = read_webm_stream,
                     .seek = seek_webm_stream,
                     .tell = tell_webm_stream,
                     .userdata = &recording};
    nestegg* demux = NULL;
    bool failed = true;

    if (nestegg_init(&demux, io, NULL, MAX_HEADER_BYTES) != 0) {
        if (!g_atomic_int_get(&bridge->stop_requested)) {
            g_warning("cannot initialize WebM/Opus demuxer");
        }
        goto finished;
    }

    if (!configure_decoder(&recording, demux)) { goto finished; }
    g_message("microphone recording started (WebM/Opus)");
    failed = false;

    while (!g_atomic_int_get(&bridge->stop_requested)) {
        nestegg_packet* packet = NULL;

        // nestegg applies its allocation limits before decoder validation.
        int result = nestegg_read_packet(demux, &packet);
        if (result <= 0) {
            failed = result < 0;
            if (failed && !g_atomic_int_get(&bridge->stop_requested)) {
                g_warning("invalid or incomplete WebM stream");
            }
            if (result == 0) { g_message("microphone stream reached end of input"); }
            break;
        }

        failed = !decode_packet(&recording, packet);
        nestegg_free_packet(packet);
        if (failed) { break; }
    }

finished:
    if (recording.decoder != NULL) { opus_decoder_destroy(recording.decoder); }
    if (demux != NULL) { nestegg_destroy(demux); }

    if (failed && !g_atomic_int_get(&bridge->stop_requested)) {
        g_warning("microphone recording stopped. Re-enable the microphone to retry");
    } else {
        g_message("microphone recording ended");
    }

    g_atomic_int_set(&bridge->worker_finished, true);
    /*
     * Wake the socket watch so the main thread joins this worker and
     * closes the session.
     */
    shutdown(bridge->client_fd, SHUT_RDWR);
    return NULL;
}

/*
 * -------------------------------------------------------------------------
 * Client lifecycle
 * -------------------------------------------------------------------------
 */

static void remove_watch(guint* watch)
{
    if (*watch != 0) {
        g_source_remove(*watch);
        *watch = 0;
    }
}

static void close_client(struct microphone_bridge* bridge)
{
    remove_watch(&bridge->client_watch);

    // Stop the worker before closing any descriptors it may still use.
    g_atomic_int_set(&bridge->stop_requested, true);
    if (bridge->client_fd >= 0) { shutdown(bridge->client_fd, SHUT_RD); }
    if (bridge->worker != NULL) {
        g_thread_join(bridge->worker);
        bridge->worker = NULL;
    }

    if (bridge->client_fd >= 0) {
        close(bridge->client_fd);
        bridge->client_fd = -1;
    }

    if (bridge->fifo_fd >= 0) {
        close(bridge->fifo_fd);
        bridge->fifo_fd = -1;
    }
}

static gboolean client_disconnected(gint fd, GIOCondition condition, gpointer data)
{
    (void)fd;
    struct microphone_bridge* bridge = data;
    bridge->client_watch = 0;

    if (!g_atomic_int_get(&bridge->worker_finished)) {
        if (condition & (G_IO_ERR | G_IO_NVAL)) {
            g_warning("microphone connection failed. Re-enable the microphone to retry");
        } else {
            g_message("microphone sender disconnected, stopping the recording");
        }
    }

    close_client(bridge);
    return G_SOURCE_REMOVE;
}

static bool start_recording(struct microphone_bridge* bridge)
{
    if (!open_fifo(bridge)) { return false; }

    g_atomic_int_set(&bridge->stop_requested, false);
    g_atomic_int_set(&bridge->worker_finished, false);

    GError* error = NULL;
    bridge->worker = g_thread_try_new("microphone", receive_recording, bridge, &error);
    if (bridge->worker == NULL) {
        g_warning("cannot start microphone worker: %s", error->message);
        g_clear_error(&error);
        return false;
    }

    return true;
}

static bool client_has_disconnected(const struct microphone_bridge* bridge)
{
    if (g_atomic_int_get(&bridge->worker_finished)) { return true; }

    char byte;
    return recv(bridge->client_fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0;
}

static gboolean accept_client(gint listener, GIOCondition condition, gpointer data)
{
    struct microphone_bridge* bridge = data;

    if (condition & (G_IO_ERR | G_IO_HUP | G_IO_NVAL)) {
        g_warning("microphone listener failed, stopping the service");
        g_main_loop_quit(bridge->loop);
        return G_SOURCE_CONTINUE;
    }

    int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
    if (client < 0) {
        if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            g_warning("cannot accept microphone connection: %s", strerror(errno));
        }
        return G_SOURCE_CONTINUE;
    }

    /*
     * Only one recording may own the pipe-source. Replace a disconnected
     * client only after the previous worker has stopped and been joined.
     */
    if (bridge->client_fd >= 0) {
        if (!client_has_disconnected(bridge)) {
            g_warning("microphone is already in use");
            close(client);
            return G_SOURCE_CONTINUE;
        }
        close_client(bridge);
    }

    bridge->client_fd = client;
    if (!start_recording(bridge)) {
        g_warning("cannot start microphone recording");
        close_client(bridge);
        return G_SOURCE_CONTINUE;
    }

    bridge->client_watch =
        g_unix_fd_add(client, G_IO_HUP | G_IO_ERR | G_IO_NVAL, client_disconnected, bridge);
    return G_SOURCE_CONTINUE;
}

/*
 * -------------------------------------------------------------------------
 * Unix socket listener
 * -------------------------------------------------------------------------
 */

static bool remove_stale_socket(const char* path, const struct sockaddr_un* address)
{
    struct stat info;
    if (lstat(path, &info) < 0) { return errno == ENOENT; }
    if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) {
        errno = EEXIST;
        return false;
    }

    int probe = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (probe < 0) { return false; }
    int result = connect(probe, (const struct sockaddr*)address, sizeof(*address));
    int connect_error = errno;
    close(probe);

    // A full backlog or pending connection also indicates a live listener.
    if (result == 0 || connect_error == EAGAIN || connect_error == EINPROGRESS ||
        connect_error == EALREADY) {
        errno = EADDRINUSE;
        return false;
    }

    if (connect_error != ECONNREFUSED && connect_error != ENOENT) {
        errno = connect_error;
        return false;
    }

    return unlink(path) == 0 || errno == ENOENT;
}

static int create_listener(const char* path)
{
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }

    strcpy(address.sun_path, path);
    if (!remove_stale_socket(path, &address)) { return -1; }

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) { return -1; }
    if (bind(fd, (struct sockaddr*)&address, sizeof(address)) < 0) {
        int bind_error = errno;
        close(fd);
        errno = bind_error;
        return -1;
    }

    if (listen(fd, 4) < 0) {
        int listen_error = errno;
        close(fd);
        unlink(path);
        errno = listen_error;
        return -1;
    }

    return fd;
}

/*
 * -------------------------------------------------------------------------
 * Service lifecycle
 * -------------------------------------------------------------------------
 */

static gboolean request_stop(gpointer data)
{
    struct microphone_bridge* bridge = data;

    g_message("received termination signal, stopping microphone service");
    g_main_loop_quit(bridge->loop);
    return G_SOURCE_CONTINUE;
}

int main(int argc, char** argv)
{
    const char* socket_path = argc > 1 ? argv[1] : "/tmp/vnc-microphone.sock";
    const char* fifo_path = argc > 2 ? argv[2] : "/tmp/vnc-microphone.fifo";

    signal(SIGPIPE, SIG_IGN);
    umask(0077);

    int listener = create_listener(socket_path);
    if (listener < 0) {
        g_printerr("cannot create microphone socket '%s': %s\n", socket_path, strerror(errno));
        return 1;
    }

    struct microphone_bridge bridge = {
        .loop = g_main_loop_new(NULL, FALSE),
        .client_fd = -1,
        .fifo_fd = -1,
        .fifo_path = fifo_path,
    };

    guint listener_watch =
        g_unix_fd_add(listener, G_IO_IN | G_IO_ERR | G_IO_HUP, accept_client, &bridge);
    guint term_watch = g_unix_signal_add(SIGTERM, request_stop, &bridge);
    guint int_watch = g_unix_signal_add(SIGINT, request_stop, &bridge);

    g_message("microphone bridge ready (WebM/Opus to 48 kHz mono s16le)");
    g_main_loop_run(bridge.loop);

    remove_watch(&listener_watch);
    remove_watch(&term_watch);
    remove_watch(&int_watch);
    close_client(&bridge);
    close(listener);
    unlink(socket_path);
    g_main_loop_unref(bridge.loop);
    return 0;
}
