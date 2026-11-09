#include <cassert>
#include <cerrno>
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <deque>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

#include <pulse/rtclock.h>
#include <pulse/timeval.h>
#include <pulse/context.h>
#include <pulse/introspect.h>
#include <pulse/mainloop.h>
#include <pulse/stream.h>
#include <pulse/error.h>
#include <pulse/mainloop-signal.h>
#include <pulse/cdecl.h>

// These includes are usually not exported by PulseAudio and are used internally
// only.
PA_C_DECL_BEGIN
#include <pulsecore/config.h>
#include <pulsecore/core-util.h>
#include <pulsecore/macro.h>
#include <pulsecore/socket-server.h>
#include <pulsecore/iochannel.h>
PA_C_DECL_END

#include <plog/Log.h>
#include <plog/Init.h>
#include <plog/Appenders/ConsoleAppender.h>
#include <plog/Formatters/MessageOnlyFormatter.h>

#include "cxxopts.hpp"

#define DEFAULT_UNIX_SOCKET_PATH "/tmp/vnc-audio.sock"
#define DEFAULT_AUDIO_RECORDER_CHANNELS "2"
#define DEFAULT_AUDIO_RECORDER_SAMPLE_RATE "48000"
#define DEFAULT_AUDIO_RECORDER_SAMPLE_FORMAT "s16le"

#define TIME_EVENT_USEC (5 * PA_USEC_PER_SEC)

#define MAX_AUDIO_RECORD_TIME_WITHOUT_CLIENTS (60 * PA_USEC_PER_SEC)

// A chunk whose peak absolute sample stays at or below this for
// SILENCE_ENTER_USEC is sent as a gap instead of PCM.
#define SILENCE_PEAK_ABS 64
#define SILENCE_ENTER_USEC (100 * PA_USEC_PER_MSEC)

// Maximum audio queued for one client. Older unsent records are dropped past this.
#define CLIENT_PENDING_LIMIT_USEC (250 * PA_USEC_PER_MSEC)

// One connected client. Pending holds complete framed records. `offset` is
// how far the current write got into pending.front().
//
// Timeline is playback duration counted as PCM sample bytes. A PCM record
// counts its sample payload. A silence gap counts the silent samples it
// stands for. The stream header counts as zero.
struct ar_client {
    struct piece {
        std::vector<uint8_t> bytes;
        // Playback duration of this record, in PCM sample bytes.
        size_t timeline_bytes = 0;
    };

    pa_iochannel *io = nullptr;
    std::deque<piece> pending;
    size_t offset = 0;
    // Playback duration still queued for this client, in PCM sample bytes.
    size_t timeline_bytes = 0;
};

// Audio recorder context.
struct ar_context {
    // The main loop.
    pa_mainloop *pa_loop = nullptr;

    // PulseAudio context.
    pa_context *pa_context = nullptr;

    // PulseAudio stream.
    pa_stream *pa_stream = nullptr;

    // Timer.
    pa_time_event *time_event = nullptr;

    // Unix socket server.
    pa_socket_server *socket_server_unix = nullptr;

    // Name of the source to record.
    std::string monitor_name;

    // The requested latency, in milliseconds.
    uint32_t latency_ms = (uint32_t)-1;

    // Buffer used to received data from clients.
    uint8_t rx_buffer[1024];

    // The time at which no clients were connected.
    pa_usec_t no_client_time = PA_USEC_INVALID;

    // List of connected clients.
    std::vector<ar_client> clients;

    // How long the monitor has been continuously below SILENCE_PEAK_ABS.
    pa_usec_t silence_run_usec = 0;

    // The sample spec.
    pa_sample_spec sample_spec = {
        .format = PA_SAMPLE_S16LE,
        .rate = 48000,
        .channels = 2,
    };

    // Framed record reused across chunks. A client that stays caught up is
    // written from this buffer. A client that falls behind gets its own copy.
    std::vector<uint8_t> send_buf;
};

std::istream& operator>>(std::istream& is, pa_sample_format_t& v)
{
    std::string test;
    is >> test;
    if (is) {
        v = pa_parse_sample_format(test.c_str());
        if (v == PA_SAMPLE_INVALID) {
            is.setstate(std::ios::failbit);
        }
    }
    return is;
}

static void quit_mainloop(ar_context *c, int retval)
{
    pa_assert(c);
    pa_assert(c->pa_loop);

    pa_mainloop_api *mainloop_api = pa_mainloop_get_api(c->pa_loop);
    pa_assert(mainloop_api);

    mainloop_api->quit(mainloop_api, retval);
}

static std::string pa_iochannel_to_string(pa_iochannel *io)
{
    pa_assert(io);

    char pname[128] = "";
    pa_iochannel_socket_peer_to_string(io, pname, sizeof(pname));

    return pname + std::string(" ") + std::to_string(pa_iochannel_get_recv_fd(io));
}

static void store_u32(uint8_t *out, uint32_t value)
{
    out[0] = static_cast<uint8_t>(value & 0xff);
    out[1] = static_cast<uint8_t>((value >> 8) & 0xff);
    out[2] = static_cast<uint8_t>((value >> 16) & 0xff);
    out[3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

static void append_u32(std::vector<uint8_t>& out, uint32_t value)
{
    size_t at = out.size();
    out.resize(at + 4);
    store_u32(out.data() + at, value);
}

// 12-byte stream header: "PCM1", rate, channels, format 1 (s16le), reserved.
static ar_client::piece make_header(const pa_sample_spec& spec)
{
    ar_client::piece piece;
    piece.bytes.reserve(12);
    piece.bytes.push_back('P');
    piece.bytes.push_back('C');
    piece.bytes.push_back('M');
    piece.bytes.push_back('1');
    append_u32(piece.bytes, spec.rate);
    piece.bytes.push_back(spec.channels);
    piece.bytes.push_back(1);
    piece.bytes.push_back(0);
    piece.bytes.push_back(0);
    return piece;
}

// One copy out of the PulseAudio buffer, so the record header and the
// samples can be written with one send. Returns the playback duration.
static size_t fill_pcm_record(ar_context *c, const uint8_t *data, size_t len)
{
    c->send_buf.resize(5 + len);
    uint8_t *out = c->send_buf.data();
    out[0] = 0;
    store_u32(out + 1, static_cast<uint32_t>(len));
    if (len > 0) {
        memcpy(out + 5, data, len);
    }
    return len;
}

static size_t fill_gap_record(ar_context *c, uint32_t frames, size_t frame_bytes)
{
    c->send_buf.resize(9);
    uint8_t *out = c->send_buf.data();
    out[0] = 1;
    store_u32(out + 1, 4);
    store_u32(out + 5, frames);
    return static_cast<size_t>(frames) * frame_bytes;
}

static bool bytes_to_frames(const pa_sample_spec& spec, size_t bytes, uint32_t& frames, size_t& frame_bytes)
{
    frame_bytes = pa_frame_size(&spec);
    if (frame_bytes == 0 || (bytes % frame_bytes) != 0) {
        return false;
    }

    size_t count = bytes / frame_bytes;
    if (count > std::numeric_limits<uint32_t>::max()) {
        return false;
    }

    frames = static_cast<uint32_t>(count);
    return true;
}

// True when every sample is at or below SILENCE_PEAK_ABS. Stops at the first
// louder sample. The bytes are s16le.
static bool pcm_chunk_is_silent(const uint8_t *data, size_t bytes)
{
    for (size_t i = 0; i + 1 < bytes; i += 2) {
        int32_t sample = static_cast<int32_t>(data[i]) |
            (static_cast<int32_t>(data[i + 1]) << 8);
        if (sample >= 32768) {
            sample -= 65536;
        }
        if (sample < 0) {
            sample = -sample;
        }
        if (sample > SILENCE_PEAK_ABS) {
            return false;
        }
    }

    return true;
}

static size_t find_client(const ar_context *c, pa_iochannel *io)
{
    for (size_t i = 0; i < c->clients.size(); i++) {
        if (c->clients[i].io == io) {
            return i;
        }
    }
    return static_cast<size_t>(-1);
}

static void disconnect_client_at(ar_context *c, size_t index, const std::string& reason)
{
    pa_assert(index < c->clients.size());

    pa_iochannel *io = c->clients[index].io;
    PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): " << reason;
    c->clients.erase(c->clients.begin() + static_cast<std::ptrdiff_t>(index));
    pa_iochannel_free(io);
}

// Drop oldest unsent records until the queued playback duration fits. A record that
// has already been partially written stays, so the byte stream is not cut
// in the middle of a frame.
static void client_drop_old(ar_client& client, size_t max_timeline)
{
    bool dropped = false;

    while (client.timeline_bytes > max_timeline) {
        // Skip the record currently being written, and skip the stream header
        // (timeline_bytes == 0). Dropping the header would not shrink the
        // queue and would desynchronize the client.
        size_t index = client.offset > 0 ? 1 : 0;
        bool found = false;
        for (; index < client.pending.size(); index++) {
            if (client.pending[index].timeline_bytes > 0) {
                found = true;
                break;
            }
        }
        if (!found) {
            break;
        }

        size_t bytes = client.pending[index].timeline_bytes;
        client.pending.erase(client.pending.begin() + static_cast<std::ptrdiff_t>(index));
        if (client.timeline_bytes >= bytes) {
            client.timeline_bytes -= bytes;
        }
        else {
            client.timeline_bytes = 0;
        }
        dropped = true;
    }

    if (dropped) {
        PLOGD << "dropped queued audio for slow client (" << pa_iochannel_to_string(client.io) << ")";
    }
}

static void client_enqueue(ar_context *c, ar_client& client, ar_client::piece record)
{
    client.timeline_bytes += record.timeline_bytes;
    client.pending.push_back(std::move(record));
    client_drop_old(client, pa_usec_to_bytes(CLIENT_PENDING_LIMIT_USEC, &c->sample_spec));
}

// Returns false when the socket failed. A short write stays queued.
static bool client_write_pending(ar_client& client)
{
    while (!client.pending.empty() && pa_iochannel_is_writable(client.io)) {
        ar_client::piece& front = client.pending.front();
        if (client.offset >= front.bytes.size()) {
            if (client.timeline_bytes >= front.timeline_bytes) {
                client.timeline_bytes -= front.timeline_bytes;
            }
            else {
                client.timeline_bytes = 0;
            }
            client.pending.pop_front();
            client.offset = 0;
            continue;
        }

        size_t left = front.bytes.size() - client.offset;
        ssize_t wrote = pa_iochannel_write(client.io, front.bytes.data() + client.offset, left);
        if (wrote < 0) {
            return false;
        }
        if (wrote == 0) {
            break;
        }

        client.offset += static_cast<size_t>(wrote);
        if (client.offset >= front.bytes.size()) {
            if (client.timeline_bytes >= front.timeline_bytes) {
                client.timeline_bytes -= front.timeline_bytes;
            }
            else {
                client.timeline_bytes = 0;
            }
            client.pending.pop_front();
            client.offset = 0;
        }
    }

    return true;
}

// Write c->send_buf. Copy it only when this client cannot take the whole
// record right now. `timeline` is the playback duration of that record.
static bool client_send(ar_context *c, ar_client& client, size_t timeline)
{
    if (client.pending.empty() && pa_iochannel_is_writable(client.io)) {
        ssize_t wrote = pa_iochannel_write(client.io, c->send_buf.data(), c->send_buf.size());
        if (wrote < 0) {
            return false;
        }
        if (static_cast<size_t>(wrote) == c->send_buf.size()) {
            return true;
        }

        // Part of the record is already on the socket. Keep the rest, and
        // keep this record from being dropped underneath that partial send.
        ar_client::piece queued;
        queued.bytes = c->send_buf;
        queued.timeline_bytes = timeline;
        client.pending.push_back(std::move(queued));
        client.offset = static_cast<size_t>(wrote);
        client.timeline_bytes += timeline;
        client_drop_old(client, pa_usec_to_bytes(CLIENT_PENDING_LIMIT_USEC, &c->sample_spec));
        return true;
    }

    ar_client::piece queued;
    queued.bytes = c->send_buf;
    queued.timeline_bytes = timeline;
    client_enqueue(c, client, std::move(queued));
    return client_write_pending(client);
}

static void broadcast(ar_context *c, size_t timeline)
{
    for (size_t i = 0; i < c->clients.size();) {
        ar_client& client = c->clients[i];

        if (pa_iochannel_is_hungup(client.io)) {
            disconnect_client_at(c, i, "hungup");
            continue;
        }

        if (!client_send(c, client, timeline)) {
            std::string reason = std::string("write failed: ") + std::strerror(errno);
            disconnect_client_at(c, i, reason);
            continue;
        }

        ++i;
    }
}

static void exit_signal_callback(pa_mainloop_api *m, pa_signal_event *e, int sig, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    switch (sig) {
        case SIGTERM:
            PLOGI << "SIGTERM signal received, terminating...";
            break;
        case SIGINT:
            PLOGI << "SIGINT signal received, terminating...";
            break;
        default:
            PLOGI << "unknown signal " << sig << " received, terminating...";
            break;
    }

    // Quit the main loop.
    quit_mainloop(c, EXIT_SUCCESS);
}

static void time_event_callback(pa_mainloop_api *m, pa_time_event *e, const struct timeval *t, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    pa_usec_t now = pa_rtclock_now();

    // Check the number of clients and stop the recording if needed.
    if (c->clients.size() == 0 && c->pa_stream) {
        if (c->no_client_time == PA_USEC_INVALID) {
            c->no_client_time = now;
        }
        else if ((now - c->no_client_time) > MAX_AUDIO_RECORD_TIME_WITHOUT_CLIENTS) {
            // Stop the audio recording.
            PLOGI << "stopping audio recording: " << (now - c->no_client_time)/PA_USEC_PER_SEC << " seconds without connected clients";
            pa_stream_disconnect(c->pa_stream);
            pa_stream_unref(c->pa_stream);
            c->pa_stream = nullptr;
        }
    }

    // Restart the timer.
    pa_context_rttime_restart(c->pa_context, e, now + TIME_EVENT_USEC);
}

void pa_stream_notify_cb(pa_stream *stream, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    switch (pa_stream_get_state(stream)) {
        case PA_STREAM_READY:
            // The stream is established. Sample spec and channel map are only
            // valid once the stream is ready.
            {
                char cmt[PA_CHANNEL_MAP_SNPRINT_MAX], sst[PA_SAMPLE_SPEC_SNPRINT_MAX];
                pa_sample_spec_snprint(sst, sizeof(sst), pa_stream_get_sample_spec(stream));
                pa_channel_map_snprint(cmt, sizeof(cmt), pa_stream_get_channel_map(stream));

                PLOGD << "audio stream is ready";
                PLOGD << "audio stream sample spec: " << sst;
                PLOGD << "audio stream sample channel map: " << cmt;

                const pa_buffer_attr *attr = pa_stream_get_buffer_attr(stream);
                if (attr) {
                    PLOGI << "audio stream buffer attr: maxlength=" << attr->maxlength
                          << ", fragsize=" << attr->fragsize;
                }
            }
            break;
        case PA_STREAM_FAILED:
        {
            // An error occurred that made the stream invalid.
            PLOGE << "audio stream error: " << pa_strerror(pa_context_errno(c->pa_context));
            quit_mainloop(c, EXIT_FAILURE);
            break;
        }
        case PA_STREAM_TERMINATED:
            // The stream has been terminated cleanly.
            PLOGI << "audio stream terminated";
            break;
        case PA_STREAM_UNCONNECTED:
            // The stream is not yet connected to any source.
        case PA_STREAM_CREATING:
            // The stream is being created.
            break;
    }
}

void pa_stream_read_cb(pa_stream *stream, const size_t /*nbytes*/, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    uint8_t *data = nullptr;
    size_t actualbytes = 0;

    // Peak data at stream.
    if (pa_stream_peek(stream, (const void**)&data, &actualbytes) != 0) {
	PLOGE << "failed to peek at stream data: " << pa_strerror(pa_context_errno(c->pa_context));
	return;
    }

    if (data == nullptr) {
        // No data in the buffer or there is a hole.
        // https://www.freedesktop.org/software/pulseaudio/doxygen/stream_8h.html#ac2838c449cde56e169224d7fe3d00824
        if (actualbytes > 0) {
            uint32_t frames = 0;
            size_t frame_bytes = 0;
            if (bytes_to_frames(c->sample_spec, actualbytes, frames, frame_bytes)) {
                broadcast(c, fill_gap_record(c, frames, frame_bytes));
            }
            else {
                PLOGD << "dropping unaligned audio hole of " << actualbytes << " bytes";
            }
            pa_stream_drop(stream);
        }
        return;
    }

    uint32_t frames = 0;
    size_t frame_bytes = 0;
    if (!bytes_to_frames(c->sample_spec, actualbytes, frames, frame_bytes) ||
        actualbytes > std::numeric_limits<uint32_t>::max()) {
        PLOGE << "dropping unaligned audio chunk of " << actualbytes << " bytes";
        pa_stream_drop(stream);
        return;
    }

    // Keep the first 100 ms of silence as PCM so a sound's tail is not cut,
    // then send gaps. A loud sample leaves silence immediately.
    pa_usec_t chunk_usec = pa_bytes_to_usec(actualbytes, &c->sample_spec);
    bool silent = pcm_chunk_is_silent(data, actualbytes);
    bool emit_gap = silent && c->silence_run_usec >= SILENCE_ENTER_USEC;
    if (silent) {
        c->silence_run_usec += chunk_usec;
    }
    else {
        c->silence_run_usec = 0;
    }

    if (emit_gap) {
        broadcast(c, fill_gap_record(c, frames, frame_bytes));
    }
    else {
        broadcast(c, fill_pcm_record(c, data, actualbytes));
    }

    // We are done with the data, remove it from the buffer.
    pa_stream_drop(stream);
}

void pa_server_info_cb(pa_context *ctx, const pa_server_info *info, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    PLOGD << "PulseAudio server default sink: " << info->default_sink_name;
    PLOGD << "PulseAudio server default source: " << info->default_source_name;

    c->monitor_name = std::string(info->default_sink_name) + ".monitor";
    PLOGD << "using PulseAudio server source: " << c->monitor_name;
}

void pa_context_notify_cb(pa_context *ctx, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    switch (pa_context_get_state(ctx)) {
        case PA_CONTEXT_UNCONNECTED:
        case PA_CONTEXT_CONNECTING:
        case PA_CONTEXT_AUTHORIZING:
        case PA_CONTEXT_SETTING_NAME:
            break;
        case PA_CONTEXT_READY:
            PLOGI << "PulseAudio server connection established";
            pa_context_get_server_info(ctx, &pa_server_info_cb, userdata);
            break;
        case PA_CONTEXT_TERMINATED:
            PLOGI << "PulseAudio server connection terminated";
            break;
        case PA_CONTEXT_FAILED:
        default:
        {
            PLOGE << "PulseAudio server connection error: " << pa_strerror(pa_context_errno(ctx));
            quit_mainloop(c, EXIT_FAILURE);
            break;
        }
    }
}

static void pa_io_callback(pa_iochannel *io, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    size_t index = find_client(c, io);
    if (index == static_cast<size_t>(-1)) {
        return;
    }

    if (pa_iochannel_is_hungup(io)) {
        PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): hungup";
        goto fail;
    }

    if (pa_iochannel_is_readable(io)) {
        int r;
        if ((r = pa_iochannel_read(io, c->rx_buffer, sizeof(c->rx_buffer))) <= 0) {
            if (r < 0 && errno == EAGAIN) {
                // Ignore the error.
            }
            else if (r < 0) {
                PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): " << std::strerror(errno);
                goto fail;
            }
            else {
                PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): peer closed connection";
                goto fail;
            }
        }
    }

    // Flush queued records. A short write stays queued for the next callback.
    if (!client_write_pending(c->clients[index])) {
        PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): write failed: " << std::strerror(errno);
        goto fail;
    }

    return;

fail:
    // Remove client from our list.
    pa_assert(index < c->clients.size());
    c->clients.erase(c->clients.begin() + static_cast<std::ptrdiff_t>(index));
    pa_iochannel_free(io);
}

static void pa_socket_server_on_connection_cb(pa_socket_server *s, pa_iochannel *io, void *userdata)
{
    ar_context *c = (ar_context *)userdata;
    pa_assert(c);

    PLOGI << "new client connected (" << pa_iochannel_to_string(io) << ")";

    // Refuse the client if we are not connected yet to the PulseAudio server.
    if (c->monitor_name.empty()) {
        PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): connection to PulseAudio server not ready yet";
        pa_iochannel_free(io);
        return;
    }

    // Add new client to our list.
    pa_assert(find_client(c, io) == static_cast<size_t>(-1));
    c->clients.push_back(ar_client{});
    ar_client& client = c->clients.back();
    client.io = io;

    // Reset time.
    c->no_client_time = PA_USEC_INVALID;

    // Queue the stream header before any PCM. The socket may not be writable
    // yet; pa_io_callback flushes the queue when it is.
    client_enqueue(c, client, make_header(c->sample_spec));

    // Set callback for read/write.
    pa_iochannel_set_callback(io, pa_io_callback, c);

    if (!client_write_pending(client)) {
        std::string reason = std::string("write failed: ") + std::strerror(errno);
        disconnect_client_at(c, c->clients.size() - 1, reason);
        return;
    }

    // Start audio recording if not already done.
    if (!c->pa_stream) {
        c->silence_run_usec = 0;
        pa_stream_flags_t flags = (c->latency_ms == (uint32_t)-1) ? PA_STREAM_NOFLAGS : PA_STREAM_ADJUST_LATENCY;

        // Set buffer attributes.  The `fragsize` field is the interesting one.  It
        // specifies size of blocks sent by the server.  This allows to control the
        // latency.
        // https://freedesktop.org/software/pulseaudio/doxygen/structpa__buffer__attr.html#abef20d3a6cab53f716846125353e56a4
        pa_buffer_attr buff_attr = {
            .maxlength = (uint32_t)-1,
            .tlength = (uint32_t)-1,
            .prebuf = (uint32_t)-1,
            .minreq = (uint32_t)-1,
            .fragsize = (c->latency_ms == (uint32_t)-1) ? (uint32_t)-1 : (uint32_t)pa_usec_to_bytes(c->latency_ms * PA_USEC_PER_MSEC, &c->sample_spec),
        };

        // Create a new, unconnected stream.
        c->pa_stream = pa_stream_new(c->pa_context, "output monitor", &c->sample_spec, nullptr /*channel map*/);
        if (!c->pa_stream) {
            PLOGE << "failed to create audio stream: " << pa_strerror(pa_context_errno(c->pa_context));
            quit_mainloop(c, EXIT_FAILURE);
            return;
        }

        // Setup stream callbacks before connecting so READY/read events are not missed.
        pa_stream_set_state_callback(c->pa_stream, &pa_stream_notify_cb, c);
        pa_stream_set_read_callback(c->pa_stream, &pa_stream_read_cb, c);

        // Connect the stream to source.
        if (pa_stream_connect_record(c->pa_stream, c->monitor_name.c_str(), &buff_attr, flags) != 0) {
            PLOGE << "failed to connect audio stream to source: " << pa_strerror(pa_context_errno(c->pa_context));
            quit_mainloop(c, EXIT_FAILURE);
            return;
        }

        PLOGD << "audio stream connected to " << c->monitor_name;
        PLOGD << "audio stream buffer metrics: maxlength="
            << ((buff_attr.maxlength == (uint32_t)-1) ? "-1" : std::to_string(buff_attr.maxlength))
            << ", fragsize="
            << ((buff_attr.fragsize == (uint32_t)-1) ? "-1" : std::to_string(buff_attr.fragsize));

        PLOGI << "audio stream recording started";
    }
}

int main(int argc, char **argv)
{
    int retval = EXIT_FAILURE;
    ar_context c;
    bool signals_initialized = false;

    std::string unix_socket_path;

    // Initialize logging.
    plog::ConsoleAppender<plog::MessageOnlyFormatter> consoleAppender;
    plog::init(plog::error, &consoleAppender);

    // Define program options.
    cxxopts::Options options("audiorecorder", "Record audio with PulseAudio and forward it to clients connected via Unix domain socket.");
    options.add_options()
        ("u,uds-path", "Path of the Unix Domain Socket to use", cxxopts::value<std::string>()->default_value(DEFAULT_UNIX_SOCKET_PATH))
        ("i,info", "Enable info logging", cxxopts::value<bool>()->default_value("false"))
        ("d,debug", "Enable debug logging", cxxopts::value<bool>()->default_value("false"))
        ("t,trace", "Enable trace logging", cxxopts::value<bool>()->default_value("false"))
        ("l,latency-msec", "Request the specified latency in msec", cxxopts::value<uint32_t>())
        ("c,channels", "The number of channels", cxxopts::value<uint8_t>()->default_value(DEFAULT_AUDIO_RECORDER_CHANNELS))
        ("r,rate", "The sample rate in Hz", cxxopts::value<uint32_t>()->default_value(DEFAULT_AUDIO_RECORDER_SAMPLE_RATE))
        ("f,format", "The sample format", cxxopts::value<pa_sample_format_t>()->default_value(DEFAULT_AUDIO_RECORDER_SAMPLE_FORMAT))
        ("h,help", "Print this help")
    ;

    // Parse program options.
    try {
        auto result = options.parse(argc, argv);
        if (result.count("help")) {
          std::cout << options.help() << std::endl;
          exit(1);
        }

        unix_socket_path = result["uds-path"].as<std::string>();

        c.sample_spec.format = result["format"].as<pa_sample_format_t>();
        c.sample_spec.rate = result["rate"].as<uint32_t>();
        c.sample_spec.channels = result["channels"].as<uint8_t>();

        if (!pa_sample_spec_valid(&c.sample_spec) || c.sample_spec.format != PA_SAMPLE_S16LE) {
            PLOGE << "invalid sample specification: format=" << pa_sample_format_to_string(c.sample_spec.format)
                  << ", rate=" << c.sample_spec.rate
                  << ", channels=" << static_cast<unsigned>(c.sample_spec.channels)
                  << " (only s16le is supported)";
            exit(1);
        }

        if (result.count("latency-msec")) {
            c.latency_ms = result["latency-msec"].as<uint32_t>();
        }

        if (result["trace"].as<bool>()) {
            plog::get()->setMaxSeverity(plog::verbose);
        }
        else if (result["debug"].as<bool>()) {
            plog::get()->setMaxSeverity(plog::debug);
        }
        else if (result["info"].as<bool>()) {
            plog::get()->setMaxSeverity(plog::info);
        }
    }
    catch (const cxxopts::exceptions::exception& e) {
        PLOGE << "failed to parse options: " << e.what();
        exit(1);
    }

    // Create main loop.
    {
        if (!(c.pa_loop = pa_mainloop_new())) {
            PLOGE << "failed to create main loop";
            goto fail;
        }
    }

    // Setup the PulseAudio context.
    {
        pa_mainloop_api *mainloop_api = pa_mainloop_get_api(c.pa_loop);
        pa_assert(mainloop_api);

        // Create new context.
        if (!(c.pa_context = pa_context_new(mainloop_api, "audiorecorder"))) {
            PLOGE << "failed to create PulseAudio context";
            goto fail;
        }

        // Connect.
        if (pa_context_connect(c.pa_context, nullptr, PA_CONTEXT_NOFLAGS, nullptr) < 0) {
            PLOGE << "failed to connect PulseAudio context: " << pa_strerror(pa_context_errno(c.pa_context));
            goto fail;
        }

        // Set the state callback.
        pa_context_set_state_callback(c.pa_context, &pa_context_notify_cb, &c);
    }

    // Setup the unix domain socket server.
    {
        pa_mainloop_api *mainloop_api = pa_mainloop_get_api(c.pa_loop);
        pa_assert(mainloop_api);

        // Remove stale socket.
        if (pa_unix_socket_remove_stale(unix_socket_path.c_str()) < 0) {
            PLOGE << "failed to remove stale UNIX socket '" << unix_socket_path << "': " << std::strerror(errno);
            goto fail;
        }

        // Create new server.
        if (!(c.socket_server_unix = pa_socket_server_new_unix(mainloop_api, unix_socket_path.c_str()))) {
            PLOGE << "failed to create unix socket server";
            goto fail;
        }

        // Set read/write callback.
        pa_socket_server_set_callback(c.socket_server_unix, pa_socket_server_on_connection_cb, &c);
    }

    // Setup signals handler.
    {
        pa_mainloop_api *mainloop_api = pa_mainloop_get_api(c.pa_loop);
        pa_assert(mainloop_api);

        if (pa_signal_init(mainloop_api) < 0) {
            PLOGE << "failed to setup signals";
            goto fail;
        }
        signals_initialized = true;
        pa_signal_new(SIGINT, exit_signal_callback, &c);
        pa_signal_new(SIGTERM, exit_signal_callback, &c);
        pa_disable_sigpipe();
    }

    // Setup the timer.
    {
        if (!(c.time_event = pa_context_rttime_new(c.pa_context, pa_rtclock_now() + TIME_EVENT_USEC, time_event_callback, &c))) {
            PLOGE << "failed to setup timer";
            goto fail;
        }
    }

    PLOGI << "server ready, waiting connections";

    // Start the main loop.
    pa_mainloop_run(c.pa_loop, &retval);

    // Free resources.
fail:

    if (c.time_event) {
        pa_assert(c.pa_loop);

        pa_mainloop_api *mainloop_api = pa_mainloop_get_api(c.pa_loop);
        pa_assert(mainloop_api);

        mainloop_api->time_free(c.time_event);
        c.time_event = nullptr;
    }

    while (!c.clients.empty()) {
        pa_iochannel *io = c.clients.back().io;
        c.clients.pop_back();
        pa_iochannel_free(io);
    }

    if (c.socket_server_unix) {
        pa_socket_server_unref(c.socket_server_unix);
        c.socket_server_unix = nullptr;
    }

    if (c.pa_stream) {
        pa_stream_disconnect(c.pa_stream);
        pa_stream_unref(c.pa_stream);
        c.pa_stream = nullptr;
    }

    if (c.pa_context) {
        pa_context_disconnect(c.pa_context);
        pa_context_unref(c.pa_context);
        c.pa_context = nullptr;
    }

    if (c.pa_loop) {
        if (signals_initialized) {
            pa_signal_done();
            signals_initialized = false;
        }
        pa_mainloop_free(c.pa_loop);
        c.pa_loop = nullptr;
    }

    return retval;
}
