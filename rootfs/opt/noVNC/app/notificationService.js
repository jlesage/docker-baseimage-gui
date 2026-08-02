import * as Log from '../core/util/logging.js';

const NotificationService = (function() {
    let webSocket = null;
    let webSocketUrl = null;
    let webSocketConnected = false;
    let webSocketConnectTimer = null;
    let notificationGranted = false;
    let started = false;

    function initialize(wsUrl) {
        webSocketUrl = wsUrl;

        if (!("Notification" in window)) {
            Log.Warn("This browser does not support notification.");
            return;
        }

        if (Notification.permission === 'granted') {
            Log.Info('Notification permission granted.');
            notificationGranted = true;
            return;
        }

        if (Notification.permission === 'denied') {
            Log.Info('Notification permission denied.');
            return;
        }

        // Permission is still "default". Browsers (especially Safari) only allow
        // Notification.requestPermission() from a user gesture, so defer the
        // prompt to the first interaction.
        Log.Info('Notification permission will be requested on the next user interaction.');
        let firstInteractionHandled = false;
        const onFirstInteraction = () => {
            if (firstInteractionHandled) {
                return;
            }
            firstInteractionHandled = true;

            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    Log.Info('Notification permission has been granted.');
                    notificationGranted = true;
                    // start() may already have been called while waiting.
                    if (started) {
                        connectWebSocket();
                    }
                } else {
                    Log.Info('Notification permission has been denied.');
                }
            });
        };
        ['pointerdown', 'touchstart'].forEach(eventType => {
            document.addEventListener(eventType, onFirstInteraction, { once: true });
        });
    }

    function start() {
        started = true;
        if (notificationGranted) {
            connectWebSocket();
        }
    }

    function stop() {
        if (webSocketConnectTimer) {
            clearTimeout(webSocketConnectTimer);
            webSocketConnectTimer = null;
        }
        disconnectWebSocket();
        started = false;
    }

    function connectWebSocket() {
        if (webSocket) return;

        Log.Info("Establishing WebSocket connection for notification service...");
        webSocket = new WebSocket(webSocketUrl);
        webSocket.binaryType = 'arraybuffer';

        webSocket.onmessage = (event) => {
            handleWebSocketMessage(event);
        };

        //webSocket.onerror = function(error) {
        //    Log.Error("WebSocket connection for notification service error:", error);
        //};

        webSocket.onopen = function(e) {
            Log.Info("WebSocket connection for notification service established");
            webSocketConnected = true;
        };

        webSocket.onclose = function(event) {
            if (event.wasClean) {
                Log.Info(`WebSocket connection for notification service closed, code=${event.code} reason=${event.reason}`);
            } else {
                // e.g. server process killed or network down
                // event.code is usually 1006 in this case
                Log.Info('WebSocket connection for notification service died');
            }

            // Destroy the connection.
            webSocket = null;
            webSocketConnected = false;

            // Attempt to re-connect.
            if (notificationGranted && started) {
                Log.Info('WebSocket reconnection for notification service will be attempted');
                webSocketConnectTimer = setTimeout(connectWebSocket, 1000);
            }
        };
    }

    function disconnectWebSocket() {
        if (!webSocket) return;
        webSocket.close();
        webSocket = null;
        webSocketConnected = false;
    }

    function handleWebSocketMessage(event) {
        const data = msgpack.decode(new Uint8Array(event.data));

        // Avoid JSON.stringify of the whole payload (future-proof if more
        // fields are added); log only the fields we care about.
        Log.Debug(`Received notification: id=${data.id}, summary=${data.summary}`);

        if (typeof data.summary !== 'string' || typeof data.body !== 'string') {
            Log.Error("Received invalid notification data.");
            return;
        }

        if (Notification.permission === 'granted') {
            // Use the assigned notification id as tag so updates (same id /
            // non-zero replaces_id) replace the existing browser notification.
            new Notification(data.summary, {
                body: data.body,
                icon: "app/images/icons/master_icon.png?v=UNIQUE_VERSION",
                tag: data.id ? `id_${data.id}` : undefined,
            });
        } else {
            Log.Info('Notification permission has been removed.');
            notificationGranted = false;
            disconnectWebSocket();
        }
    }

    // Public API
    return {
        init: function(wsUrl) {
            initialize(wsUrl);
        },

        start: function() {
            start();
        },

        stop: function() {
            stop();
        },

        initLogging: function(level) {
            Log.initLogging(level);
        },
    };
})();

export default NotificationService;
