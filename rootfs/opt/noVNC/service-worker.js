/*
 * Network-first service worker for the web UI shell.
 *
 * When the container is reachable, live files are always used. When it is
 * not, the last cached shell (HTML/JS/CSS/icons/webdata) is served so the
 * existing connecting/reconnecting spinner can show instead of the browser
 * offline page or a reverse-proxy 502. WebSockets are not intercepted.
 *
 * For more details about service workers:
 * https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers
 */

const CACHE_NAME = 'gui-shell-v1';

// First event after this worker is fetched and registered.
self.addEventListener('install', () => {
    // By default the new worker waits until every page still using the
    // old one is closed (only one version runs at a time). skipWaiting()
    // activates it immediately.
    self.skipWaiting();
});

// The worker is now in control of this app.
self.addEventListener('activate', (event) => {
    // Take over pages that are already open, so they do not need a reload.
    event.waitUntil(self.clients.claim());
});

// Fired for every request in this worker's scope.
self.addEventListener('fetch', (event) => {
    if (!shouldHandle(event.request)) {
        // Let the browser do its default thing for this request.
        return;
    }

    // Provide our own response instead of the default network request.
    event.respondWith(networkFirst(event.request));
});

function shouldHandle(request) {
    if (request.method !== 'GET') {
        return false;
    }

    let url;
    try {
        url = new URL(request.url);
    } catch (err) {
        return false;
    }

    if (url.origin !== self.location.origin) {
        return false;
    }

    // Let the browser manage the worker script itself.
    if (url.pathname.endsWith('/service-worker.js')) {
        return false;
    }

    // File-manager downloads are large, one-off GETs; do not cache them.
    if (url.pathname.includes('/download/')) {
        return false;
    }

    return true;
}

function isUpstreamUnavailable(response) {
    // Reverse proxy is up but the container is not: nginx/Caddy/Traefik
    // return 502/503/504. fetch() succeeds, so this is not a network error.
    return response && (response.status === 502 ||
                        response.status === 503 ||
                        response.status === 504);
}

async function matchFromCache(request) {
    const cache = await caches.open(CACHE_NAME);
    return cache.match(request);
}

async function networkFirst(request) {
    try {
        const response = await fetch(request);
        if (response && response.ok) {
            // Keep a copy of successful responses for when the container is
            // down. clone() is required: a response body can be read only once.
            const cache = await caches.open(CACHE_NAME);
            cache.put(request, response.clone());
        } else if (isUpstreamUnavailable(response)) {
            // Proxy answered but the container did not; use the last saved copy.
            const cached = await matchFromCache(request);
            if (cached) {
                return cached;
            }
        }
        return response;
    } catch (err) {
        // The network request failed; use a matching cached response if any.
        const cached = await matchFromCache(request);
        if (cached) {
            return cached;
        }
        throw err;
    }
}
