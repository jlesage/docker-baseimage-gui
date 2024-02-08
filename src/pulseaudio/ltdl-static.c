#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <string.h>
#include <stdbool.h>

#include <pulsecore/macro.h>

#define PA_SYMBOL_INIT(module) { "pa__init", (void*)pa__init__##module }
#define PA_SYMBOL_DONE(module) { "pa__done", (void*)pa__done__##module }
#define PA_SYMBOL_LOAD_ONCE(module) { "pa__load_once", (void*)pa__load_once__##module }
#define PA_SYMBOL_GET_N_USED(module) { "pa__get_n_used", (void*)pa__get_n_used__##module }
#define PA_SYMBOL_GET_DEPRECATE(module) { "pa__get_deprecated", (void*)pa__get_deprecated__##module }
#define PA_SYMBOL_GET_VERSION(module) { "pa__get_version", (void*)pa__get_version__##module }

#define PA_SYMBOL_AUTHOR(module) { "pa__get_author", (void*)pa__get_author__##module }
#define PA_SYMBOL_DESCRIPTION(module) { "pa__get_description", (void*)pa__get_description__##module }
#define PA_SYMBOL_USAGE(module) { "pa__get_usage", (void*)pa__get_usage__##module }
#define PA_SYMBOL_VERSION(module) { "pa__get_version", (void*)pa__get_version__##module }
#define PA_SYMBOL_DEPRECATED(module) { "pa__get_deprecated", (void*)pa__get_deprecated__##module }
#define PA_SYMBOL_LOAD_ONCE(module) { "pa__load_once", (void*)pa__load_once__##module }

typedef void pa_module;

#define PA_DECLARE(module) \
    extern int pa__init__##module(pa_module*m); \
    extern void pa__done__##module(pa_module*m); \
    extern int pa__get_n_used__##module(pa_module *m); \
    extern const char *pa__get_author__##module(void); \
    extern const char *pa__get_description__##module(void); \
    extern const char *pa__get_usage__##module(void); \
    extern const char *pa__get_version__##module(void); \
    extern const char *pa__get_deprecated__##module(void); \
    extern bool pa__load_once__##module(void); \

#define DIM(a) (sizeof(a)/sizeof(a[0]))

typedef struct {
    unsigned int refcnt;
    const char *modulename;

    struct {
        const char *name;
        void *fn;
    } syms[32];
} handle;

typedef handle* lt_dlhandle;

PA_DECLARE(null_sink);
PA_DECLARE(native_protocol_unix);

static handle g_handles[] = {
    {
        .modulename = "module-null-sink",
        .syms = {
            PA_SYMBOL_INIT(null_sink),
            PA_SYMBOL_GET_N_USED(null_sink),
            PA_SYMBOL_DONE(null_sink),
            PA_SYMBOL_AUTHOR(null_sink),
            PA_SYMBOL_DESCRIPTION(null_sink),
            PA_SYMBOL_USAGE(null_sink),
            PA_SYMBOL_VERSION(null_sink),
            PA_SYMBOL_LOAD_ONCE(null_sink),
        }
    },
    {
        .modulename = "module-native-protocol-unix",
        .syms = {
            PA_SYMBOL_INIT(native_protocol_unix),
            PA_SYMBOL_DONE(native_protocol_unix),
            PA_SYMBOL_AUTHOR(native_protocol_unix),
            PA_SYMBOL_DESCRIPTION(native_protocol_unix),
            PA_SYMBOL_USAGE(native_protocol_unix),
            PA_SYMBOL_VERSION(native_protocol_unix),
            PA_SYMBOL_LOAD_ONCE(native_protocol_unix),
        }
    },
};

static char g_last_error[128] = "";

int lt_dlinit(void)
{
    return 0;
}

int lt_dlexit(void)
{
    for (int i = 0; i < DIM(g_handles); i++) {
        g_handles[i].refcnt = 0;
    }
    return 0;
}

lt_dlhandle lt_dlopenext(const char *filename)
{
    if (filename) {
        for (int i = 0; i < DIM(g_handles); i++) {
            if (!g_handles[i].modulename) {
                break;
            }
            else if (strcmp(g_handles[i].modulename, filename) == 0) {
                g_handles[i].refcnt++;
                return &g_handles[i];
            }
        }
    }
    snprintf(g_last_error, sizeof(g_last_error), "file not found");
    return NULL;
}

int lt_dlclose(lt_dlhandle handle)
{
    if (!handle || handle->refcnt == 0) {
        snprintf(g_last_error, sizeof(g_last_error), "invalid module handle");
        return 0;
    }

    handle->refcnt--;
    return 0;
}

void *lt_dlsym(lt_dlhandle handle, const char *name)
{
    if (!handle) {
        snprintf(g_last_error, sizeof(g_last_error), "invalid module handle");
        return NULL;
    }

    if (name) {
        for (int i = 0; i < DIM(handle->syms); i++) {
            if (!handle->syms[i].name) {
                break;
            }
            else if (strcmp(handle->syms[i].name, name) == 0) {
                return handle->syms[i].fn;
            }
        }
    }
    snprintf(g_last_error, sizeof(g_last_error), "symbol not found");
    return NULL;
}

int lt_dlforeachfile(const char *search_path, int (*func) (const char *filename, void * data), void * data)
{
    if (func) {
        for (int i = 0; i < DIM(g_handles); i++) {
            if (!g_handles[i].modulename) {
                break;
            }
            func(g_handles[i].modulename, data);
        }
    }
    return 0;
}

int lt_dlsetsearchpath(const char *search_path)
{
    return 0;
}

const char * lt_dlgetsearchpath(void)
{
    return NULL;
}

const char * lt_dlerror(void)
{
    if (g_last_error[0]) {
        return g_last_error;
    }
    else {
        return NULL;
    }
}

typedef void lt_dlsymlist;
int lt_dlpreload_default(const lt_dlsymlist *preloaded)
{
    return 0;
}

void pa_ltdl_init(void)
{
    pa_assert_se(lt_dlinit() == 0);
}

void pa_ltdl_done(void)
{
    pa_assert_se(lt_dlexit() == 0);
}
