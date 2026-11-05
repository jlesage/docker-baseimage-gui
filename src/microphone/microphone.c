// Receive WebM/Ogg Opus over a Unix socket, decode with GStreamer,
// and write 48 kHz mono s16le to PulseAudio's pipe-source FIFO.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glib-unix.h>
#include <gst/gst.h>
#include <signal.h>
#include <stdbool.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// Link and register only the plugins used by the microphone pipeline.
#ifdef MICROPHONE_STATIC_GSTREAMER
GST_PLUGIN_STATIC_DECLARE(coreelements);
GST_PLUGIN_STATIC_DECLARE(playback);
GST_PLUGIN_STATIC_DECLARE(typefindfunctions);
GST_PLUGIN_STATIC_DECLARE(audioconvert);
GST_PLUGIN_STATIC_DECLARE(audioresample);
GST_PLUGIN_STATIC_DECLARE(opus);
GST_PLUGIN_STATIC_DECLARE(ogg);
GST_PLUGIN_STATIC_DECLARE(matroska);
#endif

enum {
    DISCONNECT_DRAIN_MS = 250,
    FIFO_BUFFER_BYTES = 4096,
    FIFO_CHECK_SECONDS = 1,
};

/*
 * fdsrc -> decodebin (decode WebM/Ogg Opus)
 *       -> audioconvert -> audioresample
 *       -> convert to raw PCM (S16LE, 48 kHz, mono, interleaved)
 *       -> bounded 200 ms queue (drop oldest buffers when full)
 *       -> fdsink (write PCM to the capture FIFO; no clock synchronization)
 */
static const char* pipeline_description =
    "fdsrc name=browser timeout=10000000 ! "
    "decodebin caps=audio/x-raw ! audioconvert ! audioresample ! "
    "audio/x-raw,format=S16LE,rate=48000,channels=1,layout=interleaved ! "
    "queue max-size-time=200000000 max-size-bytes=0 max-size-buffers=0 leaky=downstream ! "
    "fdsink name=capture sync=false async=false";

struct bridge {
    GMainLoop* loop;

    GstElement* pipeline;
    guint bus_watch;
    guint client_watch;
    guint drain_watch;
    int client;
    int fifo;

    const char* fifo_path;
    struct stat fifo_info;
};

static void remove_watch(guint* watch)
{
    if (*watch != 0) {
        g_source_remove(*watch);
        *watch = 0;
    }
}

static bool same_file(const struct stat* first, const struct stat* second)
{ return first->st_dev == second->st_dev && first->st_ino == second->st_ino; }

static bool owned_fifo(const struct stat* info)
{ return S_ISFIFO(info->st_mode) && info->st_uid == getuid(); }

static void close_client(struct bridge* bridge)
{
    remove_watch(&bridge->client_watch);
    remove_watch(&bridge->drain_watch);
    remove_watch(&bridge->bus_watch);

    // Stop streaming threads before closing the descriptors they use.
    if (bridge->pipeline != NULL) {
        gst_element_set_state(bridge->pipeline, GST_STATE_NULL);
        gst_object_unref(bridge->pipeline);
        bridge->pipeline = NULL;
    }
    if (bridge->client >= 0) {
        close(bridge->client);
        bridge->client = -1;
    }
    if (bridge->fifo >= 0) {
        close(bridge->fifo);
        bridge->fifo = -1;
    }
}

static gboolean finish_disconnected_client(gpointer data)
{
    struct bridge* bridge = data;
    bridge->drain_watch = 0;  // This callback removes its own source on return.
    close_client(bridge);
    return G_SOURCE_REMOVE;
}

static gboolean client_disconnected(gint fd, GIOCondition condition, gpointer data)
{
    (void)fd;
    (void)condition;

    struct bridge* bridge = data;
    bridge->client_watch = 0;
    bridge->drain_watch = g_timeout_add(DISCONNECT_DRAIN_MS, finish_disconnected_client, bridge);
    return G_SOURCE_REMOVE;
}

static gboolean pipeline_message(GstBus* bus, GstMessage* message, gpointer data)
{
    (void)bus;
    struct bridge* bridge = data;

    switch (GST_MESSAGE_TYPE(message)) {
        case GST_MESSAGE_ERROR: {
            GError* error = NULL;
            gchar* debug = NULL;
            gst_message_parse_error(message, &error, &debug);
            g_warning("microphone pipeline: %s", error->message);
            g_debug("%s", debug != NULL ? debug : "No additional pipeline details");
            g_clear_error(&error);
            g_free(debug);
            break;
        }
        case GST_MESSAGE_EOS:
            g_message("microphone recording ended");
            break;
        case GST_MESSAGE_ELEMENT: {
            const GstStructure* details = gst_message_get_structure(message);
            if (details == NULL || !gst_structure_has_name(details, "GstFdSrcTimeout")) {
                return G_SOURCE_CONTINUE;
            }
            g_warning("microphone sender supplied no data for 10 seconds");
            break;
        }
        default:
            return G_SOURCE_CONTINUE;
    }

    bridge->bus_watch = 0;  // This callback removes its own watch on return.
    close_client(bridge);
    return G_SOURCE_REMOVE;
}

static bool open_fifo(struct bridge* bridge)
{
    struct stat path_info;
    if (lstat(bridge->fifo_path, &path_info) < 0) {
        g_warning("cannot inspect microphone FIFO '%s': %s", bridge->fifo_path, strerror(errno));
        return false;
    }
    if (!owned_fifo(&path_info)) {
        g_warning("microphone path must be a FIFO owned by this user: %s", bridge->fifo_path);
        return false;
    }

    bridge->fifo = open(bridge->fifo_path, O_WRONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (bridge->fifo < 0) {
        g_warning("cannot open microphone FIFO '%s': %s", bridge->fifo_path, strerror(errno));
        return false;
    }
    if (fstat(bridge->fifo, &bridge->fifo_info) < 0) {
        g_warning("cannot inspect opened microphone FIFO: %s", strerror(errno));
        return false;
    }
    if (!owned_fifo(&bridge->fifo_info) || !same_file(&bridge->fifo_info, &path_info)) {
        g_warning("microphone FIFO changed while opening it: %s", bridge->fifo_path);
        return false;
    }

    // Limit stale kernel buffering as well as the pipeline's decoded queue.
    if (fcntl(bridge->fifo, F_SETPIPE_SZ, FIFO_BUFFER_BYTES) < 0) {
        g_warning("could not reduce microphone FIFO capacity: %s", strerror(errno));
    }
    return true;
}

static bool configure_pipeline_fds(struct bridge* bridge)
{
    GstElement* input = gst_bin_get_by_name(GST_BIN(bridge->pipeline), "browser");
    GstElement* output = gst_bin_get_by_name(GST_BIN(bridge->pipeline), "capture");
    bool ready = input != NULL && output != NULL;

    if (ready) {
        g_object_set(input, "fd", bridge->client, NULL);
        g_object_set(output, "fd", bridge->fifo, NULL);
    } else {
        g_warning("microphone pipeline is missing its input or output element");
    }

    if (input != NULL) gst_object_unref(input);
    if (output != NULL) gst_object_unref(output);
    return ready;
}

static bool start_pipeline(struct bridge* bridge)
{
    if (!open_fifo(bridge)) return false;

    GError* error = NULL;
    bridge->pipeline = gst_parse_launch(pipeline_description, &error);
    if (error != NULL || bridge->pipeline == NULL) {
        g_warning("cannot create microphone pipeline: %s",
                  error != NULL ? error->message : "no pipeline was returned");
        g_clear_error(&error);
        return false;
    }

    if (!configure_pipeline_fds(bridge)) return false;

    GstBus* bus = gst_element_get_bus(bridge->pipeline);
    bridge->bus_watch = gst_bus_add_watch(bus, pipeline_message, bridge);
    gst_object_unref(bus);

    if (gst_element_set_state(bridge->pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        g_warning("cannot start microphone pipeline");
        return false;
    }

    g_message("microphone recording connected (WebM/Ogg Opus)");
    return true;
}

static bool client_has_disconnected(const struct bridge* bridge)
{
    if (bridge->drain_watch != 0) { return true; }
    char byte;
    return recv(bridge->client, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0;
}

static gboolean accept_client(gint listener, GIOCondition condition, gpointer data)
{
    struct bridge* bridge = data;
    if (condition & (G_IO_ERR | G_IO_HUP | G_IO_NVAL)) {
        g_warning("microphone listener failed; stopping the service");
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
    // Only one recording may own the pipe-source. A disconnected client
    // may be replaced immediately rather than waiting for its drain timer.
    if (bridge->client >= 0) {
        if (!client_has_disconnected(bridge)) {
            close(client);
            return G_SOURCE_CONTINUE;
        }
        close_client(bridge);
    }

    bridge->client = client;
    if (!start_pipeline(bridge)) {
        // Also releases resources acquired by a partially initialized pipeline.
        close_client(bridge);
        return G_SOURCE_CONTINUE;
    }
    bridge->client_watch =
        g_unix_fd_add(client, G_IO_HUP | G_IO_ERR | G_IO_NVAL, client_disconnected, bridge);
    return G_SOURCE_CONTINUE;
}

static gboolean check_fifo(gpointer data)
{
    struct bridge* bridge = data;
    if (bridge->client < 0) { return G_SOURCE_CONTINUE; }

    struct stat info;
    if (lstat(bridge->fifo_path, &info) < 0 || !owned_fifo(&info) ||
        !same_file(&info, &bridge->fifo_info)) {
        g_warning("microphone FIFO changed; enable the microphone again after PulseAudio restarts");
        close_client(bridge);
    }
    return G_SOURCE_CONTINUE;
}

static bool remove_stale_socket(const char* path, const struct sockaddr_un* address)
{
    struct stat info;
    if (lstat(path, &info) < 0) { return errno == ENOENT; }
    if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) {
        errno = EEXIST;
        return false;
    }

    int probe = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (probe < 0) { return false; }
    int result = connect(probe, (const struct sockaddr*)address, sizeof(*address));
    int connect_error = errno;
    close(probe);
    if (result == 0) {
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

static gboolean request_stop(gpointer data)
{
    struct bridge* bridge = data;
    g_main_loop_quit(bridge->loop);
    return G_SOURCE_CONTINUE;
}

static void register_gstreamer_plugins(void)
{
#ifdef MICROPHONE_STATIC_GSTREAMER
    GST_PLUGIN_STATIC_REGISTER(coreelements);
    GST_PLUGIN_STATIC_REGISTER(playback);
    GST_PLUGIN_STATIC_REGISTER(typefindfunctions);
    GST_PLUGIN_STATIC_REGISTER(audioconvert);
    GST_PLUGIN_STATIC_REGISTER(audioresample);
    GST_PLUGIN_STATIC_REGISTER(opus);
    GST_PLUGIN_STATIC_REGISTER(ogg);
    GST_PLUGIN_STATIC_REGISTER(matroska);
#endif
}

int main(int argc, char** argv)
{
    const char* socket_path = argc > 1 ? argv[1] : "/tmp/vnc-microphone.sock";
    const char* fifo_path = argc > 2 ? argv[2] : "/tmp/vnc-microphone.fifo";
    gst_init(NULL, NULL);
    register_gstreamer_plugins();

    signal(SIGPIPE, SIG_IGN);
    umask(0077);

    int listener = create_listener(socket_path);
    if (listener < 0) {
        g_printerr("cannot create microphone socket '%s': %s\n", socket_path, strerror(errno));
        gst_deinit();
        return 1;
    }
    struct bridge bridge = {
        .loop = g_main_loop_new(NULL, FALSE),
        .client = -1,
        .fifo = -1,
        .fifo_path = fifo_path,
    };
    guint listener_watch =
        g_unix_fd_add(listener, G_IO_IN | G_IO_ERR | G_IO_HUP, accept_client, &bridge);
    guint fifo_watch = g_timeout_add_seconds(FIFO_CHECK_SECONDS, check_fifo, &bridge);
    guint term_watch = g_unix_signal_add(SIGTERM, request_stop, &bridge);
    guint int_watch = g_unix_signal_add(SIGINT, request_stop, &bridge);

    g_message("microphone bridge ready (WebM/Ogg Opus -> s16le, 48000 Hz, mono)");
    g_main_loop_run(bridge.loop);

    remove_watch(&listener_watch);
    remove_watch(&fifo_watch);
    remove_watch(&term_watch);
    remove_watch(&int_watch);
    close_client(&bridge);
    close(listener);
    unlink(socket_path);
    g_main_loop_unref(bridge.loop);
    gst_deinit();
    return 0;
}
