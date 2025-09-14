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

        // Handle the state of notification permission.
        if (!("Notification" in window)) {
            Log.Warn("This browser does not support notification.")
        } else if (Notification.permission === 'granted') {
            Log.Info('Notification permission granted.');
            notificationGranted = true;
        } else if (Notification.permission === 'denied') {
            Log.Info('Notification permission denied.');
            notificationGranted = false;
        } else {
            // Ask permission.
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    Log.Info('Notification permission has been granted.');
                    notificationGranted = true;

                    // Call the start function again because it might have first
                    // been called while permission not granted.
                    if (started) {
                        start();
                    }
                } else {
                    Log.Info('Notification permission has been denied.');
                }
            });
        }
    }

    function start() {
        if (notificationGranted) {
            connectWebSocket();
            started = true;
        }
    }

    function stop() {
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
            if (notificationGranted) {
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

        Log.Debug("Received message: " + JSON.stringify(data));

        if (!data.summary || !data.body) {
            Log.Error("Received invalid notification data.");
            return;
        }

        if (Notification.permission === 'granted') {
            new Notification(data.summary, {
                body: data.body,
                icon: "app/images/icons/master_icon.png?v=UNIQUE_VERSION",
                tag: data.replacesID ? `id_${data.replacesID}` : undefined,
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
