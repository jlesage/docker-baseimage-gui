#include <string>
#include <set>
#include <cerrno>
#include <csignal>
#include <cassert>

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
#define DEFAULT_AUDIO_RECORDER_SAMPLE_RATE "44100"
#define DEFAULT_AUDIO_RECORDER_SAMPLE_FORMAT "s16le"

#define TIME_EVENT_USEC (5 * PA_USEC_PER_SEC)

#define MAX_AUDIO_RECORD_TIME_WITHOUT_CLIENTS (60 * PA_USEC_PER_SEC)

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
    std::set<pa_iochannel *> clients;

    // The sample spec.
    pa_sample_spec sample_spec = {
        .format = PA_SAMPLE_S16LE,
        .rate = 44100,
        .channels = 2,
    };
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
            // The stream is established.
            PLOGD << "audio stream is ready";
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
            // Hole in the buffer. We must drop it.
            pa_stream_drop(stream);
        }
        return;
    }

    // Send data to all clients.
    for (auto it = c->clients.begin(); it != c->clients.end();) {
        std::string disconnect_reason;

        if (pa_iochannel_is_hungup(*it)) {
            disconnect_reason = "hungup";
        }
        else {
            ssize_t r = pa_iochannel_write(*it, (void*)data, actualbytes);
            if (r < 0) {
                disconnect_reason = "write failed: " + std::string(std::strerror(errno));
            }
            else if (r == 0) {
                // Retry would be needed.  Looks like the client is too slow
                // to process the data.  Client will miss data.
                PLOGV << "data dropped for client (" << pa_iochannel_to_string(*it) << ")";
            }
        }

        if (!disconnect_reason.empty()) {
            PLOGI << "disconnecting client (" << pa_iochannel_to_string(*it) << "): " << disconnect_reason;
            pa_iochannel_free(*it);
            pa_assert(c->clients.count(*it) > 0);
            it = c->clients.erase(it);
        }
        else {
            ++it;
        }
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

    if (pa_iochannel_is_hungup(io)) {
        PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): hungup";
        goto fail;
    }

    if (pa_iochannel_is_readable(io)) {
        int r;
        if ((r = pa_iochannel_read(io, c->rx_buffer, sizeof(c->rx_buffer) <= 0))) {
            if (r < 0 && errno == EAGAIN) {
                // Ignore the error.
                return;
            }
            else if (r < 0) {
                PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): " << std::strerror(errno);
            }
            else {
                PLOGI << "disconnecting client (" << pa_iochannel_to_string(io) << "): peer closed connection";
            }
            goto fail;
        }
    }

    return;

fail:
    // Remove client from our list.
    pa_assert(c->clients.count(io) > 0);
    c->clients.erase(io);
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
    pa_assert(c->clients.count(io) == 0);
    c->clients.insert(io);

    // Reset time.
    c->no_client_time = PA_USEC_INVALID;

    // Set callback for read/write.
    pa_iochannel_set_callback(io, pa_io_callback, c);

    // Start audio recording if not already done.
    if (!c->pa_stream) {
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

        {
            char cmt[PA_CHANNEL_MAP_SNPRINT_MAX], sst[PA_SAMPLE_SPEC_SNPRINT_MAX];
            pa_sample_spec_snprint(sst, sizeof(sst), pa_stream_get_sample_spec(c->pa_stream));
            pa_channel_map_snprint(cmt, sizeof(cmt), pa_stream_get_channel_map(c->pa_stream));

            PLOGD << "audio stream sample spec: " << sst;
            PLOGD << "audio stream sample channel map: " << cmt;
        }

        // Setup stream callbacks.
        pa_stream_set_state_callback(c->pa_stream, &pa_stream_notify_cb, c);
        pa_stream_set_read_callback(c->pa_stream, &pa_stream_read_cb, c);

        PLOGI << "audio stream recording started";
    }
}

int main(int argc, char **argv)
{
    int retval = EXIT_FAILURE;
    ar_context c;

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
        pa_iochannel *io = *c.clients.begin();
        pa_iochannel_free(io);
        c.clients.erase(io);
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
        pa_signal_done();
        pa_mainloop_free(c.pa_loop);
        c.pa_loop = nullptr;
    }

    return retval;
}
