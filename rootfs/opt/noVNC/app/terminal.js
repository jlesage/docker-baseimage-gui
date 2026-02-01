import * as Log from '../core/util/logging.js';
import "./xterm.js";
import "./xterm-addon-fit.js";

const TerminalService = (function() {
    let webSocket = null;
    let webSocketUrl = null;
    let webSocketConnected = false;
    let webSocketConnectTimer = null;

    let terminalContainerId = null;

    let terminal = null;
    let terminalFitAddon = null;

    let moduleEventCallbacks = {
        'close': [],
        'enabled': [],
        'disabled': [],
    };

    function initialize(wsUrl, containerId) {
        webSocketUrl = wsUrl;
        terminalContainerId = containerId
    }

    function openTerminal() {
        if (terminal) return;

        Log.Info("Opening terminal.");

        // Create terminal.
        terminal = new Terminal({
            cursorBlink: true,
            fontFamily: 'monospace',
        })

        // Setup fit addon.
        terminalFitAddon = new FitAddon.FitAddon();
        terminal.loadAddon(terminalFitAddon);

        // Disable terminal for now. It will be re-enabled once the WebSocket
        // connection is established.
        disableTerminal();

        // Open terminal within element.
        terminal.open(document.getElementById(terminalContainerId));
        terminalFitAddon.fit();
        Log.Debug(`Terminal size: ${terminal.cols},${terminal.rows}`);

        // Setup data handler.
        terminal.onData(data => {
            if (webSocket && webSocketConnected) {
                webSocket.send(new TextEncoder().encode(data));
            }
        });

        // Establish WebSocket connection.
        connectWebSocket();
    }

    function closeTerminal() {
        if (!terminal) return;

        Log.Info("Closing terminal.");

        // Dispose the terminal.
        terminalFitAddon.dispose();
        terminalFitAddon = null;
        terminal.dispose();
        terminal = null;

        // Close the WebSocket connection.
        disconnectWebSocket();

        // Invoke the close callbacks.
        moduleEventCallbacks['close'].forEach(function (func, index) {
            func();
        });
    }

    function resizeTerminal() {
        if (!terminal) return;
        terminalFitAddon.fit();
        Log.Debug(`Terminal resized to ${terminal.cols},${terminal.rows}`);
        if (webSocket && webSocketConnected) {
            webSocket.send(`resize:${terminal.cols},${terminal.rows}`);
        }
    }

    function enableTerminal() {
        if (!terminal) return;
        terminal.options.disableStdin = false;
        terminal.focus();

        // Invoke the enabled callbacks.
        moduleEventCallbacks['enabled'].forEach(function (func, index) {
            func();
        });
    }

    function disableTerminal() {
        if (!terminal) return;
        terminal.options.disableStdin = true;

        // Invoke the disabled callbacks.
        moduleEventCallbacks['disabled'].forEach(function (func, index) {
            func();
        });
    }

    function connectWebSocket() {
        if (webSocket) return;

        if (webSocketConnectTimer) {
            clearTimeout(webSocketConnectTimer);
            webSocketConnectTimer = null;
        }

        Log.Info("Establishing WebSocket connection for terminal service...");
        webSocket = new WebSocket(webSocketUrl);
        webSocket.binaryType = 'arraybuffer';

        // WebScoket message handler.
        webSocket.onmessage = (event) => {
            handleWebSocketMessage(event);
        };

        //webSocket.onerror = function(error) {
        //    Log.Error("WebSocket connection for terminal service error:", error);
        //};

        // WebSocket open handler.
        webSocket.onopen = function(e) {
            Log.Info("WebSocket connection for terminal service established");
            webSocketConnected = true;
            webSocket.send(`resize:${terminal.cols},${terminal.rows}`);

            // Enable the terminal.
            enableTerminal();
        };

        // WebSocket close handler.
        webSocket.onclose = function(event) {
            const cleanDisconnect = event.wasClean;
            if (cleanDisconnect) {
                Log.Info(`WebSocket connection for terminal closed, code=${event.code} reason=${event.reason}`);
            } else {
                // e.g. server process killed or network down
                // event.code is usually 1006 in this case
                Log.Info(`WebSocket connection for terminal died, code=${event.code} reason=${event.reason}`);
            }

            // Disable the terminal.
            disableTerminal();

            // Destroy the WebSocket connection.
            disconnectWebSocket();

            // Close the terminal on a clean disconnection, else attempt to
            // re-connect.
            if (terminal) {
                if (cleanDisconnect) {
                    // Close the terminal.
                    closeTerminal();
                } else {
                    // Attempt to re-connect.
                    Log.Info('WebSocket reconnection for terminal service will be attempted');
                    webSocketConnectTimer = setTimeout(connectWebSocket, 1000);
                }
            }
        };
    }

    function disconnectWebSocket() {
        if (webSocket) {
            webSocket.close();
            webSocket = null;
            webSocketConnected = false;
        }

        if (webSocketConnectTimer) {
            clearTimeout(webSocketConnectTimer);
            webSocketConnectTimer = null;
        }
    }

    function handleWebSocketMessage(event) {
        if (!terminal) return;

        Log.Debug("Received message from WebSocket.");

        if (event.data instanceof ArrayBuffer) {
            // Write data to terminal.
            terminal.write(new Uint8Array(event.data));
        } else if (typeof event.data === 'string') {
            // Handle command.
            if (event.data === 'terminate') {
                Log.Info("Received terminate command from WebSocket.");
                closeTerminal();
            } else {
                Log.Warn(`Received unknown command from WebSocket: ${event.data}`);
            }
        } else {
            Log.Error("Received invalid message from WebSocket.");
        }
    }

    // Public API
    return {
        init: function(wsUrl, containerId) {
            initialize(wsUrl, containerId);
        },

        initLogging: function(level) {
            Log.initLogging(level);
        },

        open: function() {
            openTerminal();
        },

        close: function() {
            closeTerminal();
        },

        resize: function() {
            resizeTerminal();
        },

        addEventListener: function(e, f) {
            if (moduleEventCallbacks[e] !== undefined) {
                moduleEventCallbacks[e].push(f);
            }
        },
    };
})();

export default TerminalService;
