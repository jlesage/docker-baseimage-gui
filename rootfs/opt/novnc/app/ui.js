/*
 * UI for noVNC HTML5 VNC client.
 *
 * This UI for noVNC is optimized to access the Graphical User Interface (GUI)
 * of a single running application.  This is perfect for applications running
 * inside a Docker container.
 *
 * Here are the parameters used by the UI.  They can be overriden via query
 * string:
 *   - logging=<debug|info|warn|error>
 *     Logging level.  Default: 'warn'.
 *   - app_name<string>
 *     Override the application's name.  Default: not set (no override).
 *   - host=<host>
 *     VNC server host to which a Websocket connection is established.  Default:
 *     Host of the server that served this file.
 *   - port=<port>
 *     VNC server port to which a Websocket connection is established.  Default:
 *     Port of the server that served this file.
 *   - password=<string>
 *     VNC server password.  Default: not set.
 *   - path=<string>
 *     Websocket path.  Default: 'websockify'.
 *   - encrypt=<0|1>
 *     Encrypt websocket connection.  Defaut: 0.
 *   - repeaterID=<string>
 *     RepeaterID to connect to.  Default: not set.
 *   - true_color=<0|1>
 *     Request true color pixel data.  Default: 1.
 *   - cursor=<0|1>
 *     Request locally rendered cursor.  Default: 0 when touch interface
 *     available, else 1.
 *   - view_only=<0|1>
 *     Disable client mouse/keyboard.  Default: 0.
 */

"use strict";

var UI = {

  rfb: null,
  rfb_state: 'loaded',

  appName: $('#appName').text(),

  isSafari: false,
  isTouchDevice: false,

  host: null,
  port: null,
  password: null,
  path: null,

  rfbUpdateStateCallbacks: $.Callbacks(),
  rfbFBUCompleteCallbacks: $.Callbacks(),
  rfbDesktopNameCallbacks: $.Callbacks(),
  rfbPasswordRequiredCallbacks: $.Callbacks(),
  rfbOnMouseButtonCallbacks: $.Callbacks(),
  rfbOnMouseMoveCallbacks: $.Callbacks(),

  start: function() {
    console.info("Starting UI...");
    UI.init();
    if (UI.rfb) {
      UI.rfb.connect(UI.host, UI.port, UI.password, UI.path);
    }
  },

  init: function() {
    // Logging
    UI.initLogging();

    // Detect Safari browser
    UI.isSafari = (navigator.userAgent.indexOf('Safari') !== -1 &&
                   navigator.userAgent.indexOf('Chrome') === -1);
    Util.Debug("Safari browser: " + UI.isSafari);

    // Detect if touch is interface available.
    UI.isTouchDevice = ('ontouchstart' in document.documentElement) ||
                        // required for Chrome debugger
                        (document.ontouchstart !== undefined) ||
                        // required for MS Surface
                        (navigator.maxTouchPoints > 0) ||
                        (navigator.msMaxTouchPoints > 0);
    Util.Debug("Touch interface available: " + UI.isTouchDevice);

    // Connection settings
    UI.initConnectSettings();

    // App name
    UI.appNameUpdate(WebUtil.getConfigVar('app_name', null));

    // RFB
    if (!UI.initRFB()) {
      return;
    }

    // Event handlers
    UI.initGlobalEventHandlers();

    // Initialize tooltip
    $('[data-toggle="tooltip"]').tooltip();

    // Start modules
    ModuleMgr.start();
  },

  initLogging: function() {
    WebUtil.init_logging(WebUtil.getConfigVar('logging', 'warn'));
  },

  initConnectSettings: function() {
    Util.Debug(">> initConnectSettings");

    // Get the VNC server host used to establish the Websocket connection.  By
    // default, use the host of server that served this file.
    UI.host = WebUtil.getConfigVar('host', window.location.hostname);
    // If there are at least two colons in there, it is likely an IPv6
    // address. Check for square brackets and add them if missing.
    if(UI.host.search(/^.*:.*:.*$/) != -1) {
        if(UI.host.charAt(0) != "[")
            UI.host = "[" + UI.host;
        if(UI.host.charAt(UI.host.length-1) != "]")
            UI.host = UI.host + "]";
    }

    // Get the VNC server port used to establish the Websocket connection.  By
    // default, use the same HTTP port of the server that served this file.
    UI.port = WebUtil.getConfigVar('port', Number(window.location.port));
    if (!UI.port) {
        // Port will not be set when using default ones.
        if (window.location.protocol === "https:") {
            UI.port = "443"
        }
        else {
            UI.port = "80"
        }
    }

    // Get the VNC password.
    UI.password = WebUtil.getConfigVar('password', '');

    // Get the path.
    UI.path = WebUtil.getConfigVar('path', window.location.pathname.substr(1) + 'websockify');

    Util.Debug("<< initConnectSettings");
  },

  initRFB: function() {
    try {
      UI.rfb = new RFB({'target': $('#rfbScreen')[0],
                        'encrypt': WebUtil.getConfigVar('encrypt',
                                     (window.location.protocol === "https:")),
                        'repeaterID': WebUtil.getConfigVar('repeaterID', ''),
                        'true_color': WebUtil.getConfigVar('true_color', true),
                        'local_cursor': WebUtil.getConfigVar('cursor', !UI.isTouchDevice),
                        'shared': true,
                        'view_only': WebUtil.getConfigVar('view_only', false),
                        'onUpdateState': UI.rfbOnUpdateState,
                        'onPasswordRequired': UI.rfbOnPasswordRequired,
                        //'onClipboard': UI.clipboardReceive,
                        'onFBUComplete': UI.rfbOnFBUComplete,
                        'onDesktopName': UI.rfbOnDesktopName,
                       });

      // Override the onMouseButton callback.
      this.rfbOriginalOnMouseButton = this.rfb.get_mouse().get_onMouseButton();
      this.rfbOriginalOnMouseMove = this.rfb.get_mouse().get_onMouseMove();
      this.rfb.get_mouse().set_onMouseButton(this.rfbOnMouseButton.bind(this));
      this.rfb.get_mouse().set_onMouseMove(this.rfbOnMouseMove.bind(this));

      return true;
    } catch (exc) {
      var msg = "Unable to create RFB client -- " + exc;
      Util.Error(msg);
      UI.rfbOnUpdateState(null, 'fatal', null, 'Unable to create RFB client -- ' + exc);
      return false;
    }
  },

  initGlobalEventHandlers: function() {
    // Remove focus from buttons after a modal is closed.
    $('body').on('hidden.bs.modal', '.modal', function(event) {
      $('.btn').blur();
    });

    // Remove focus from button after click.
    $(".btn").mouseup(function() {
      $(this).blur();
    });

    // When navbar is collapsible and open, close it when a button is clicked.
    $('.navbar-btn').on('click', function(event) {
      if ($('.navbar-collapse').hasClass('collapse in')) {
        $('.navbar-collapse').collapse('hide');
      }
    });
  },

  /****************************************************************************
   * RFB callbacks
   ****************************************************************************/

  rfbOnFBUComplete: function(rfb, fbu) {
    // Invoke registered callbacks.
    UI.rfbFBUCompleteCallbacks.fire(rfb, fbu);
    // After doing this once, we remove the callback.
    UI.rfb.set_onFBUComplete(function() { });
  },

  rfbOnDesktopName: function(rfb, name) {
    // Invoke registered callbacks.
    UI.rfbDesktopNameCallbacks.fire(rfb, name);
  },

  rfbOnPasswordRequired: function(rfb, msg) {
    // Invoke registered callbacks.
    if (UI.rfbPasswordRequiredCallbacks.has()) {
      UI.rfbPasswordRequiredCallbacks.fire(rfb, msg);
    }
    else {
      // No password support.  Just send back an invalid password to trigger and
      // show the proper error.
      Util.Warn("Connection with the VNC server required a password but "+
                "password support in UI is disabled.");
      UI.rfb.sendPassword('wefo23dfmfj498fjf93hfw2309daa[sd85983ct2378K#*2129');
    }
  },

  rfbOnUpdateState: function(rfb, state, oldstate, msg) {
    var statusClasses = ["fa", "fa-lg"];

    Util.Debug(">> UI.rfbOnUpdateState: state=" + state + ", oldstate=" + oldstate +
               ", msg=" + msg);

    switch (state) {
      case 'failed':
      case 'fatal':
        statusClasses.push("fa-times-circle");
        statusClasses.push("text-danger");
        break;
      case 'normal':
        if (UI.rfb.get_encrypt()) {
          statusClasses.push("fa-lock");
        } else {
          statusClasses.push("fa-unlock-alt");
        }
        statusClasses.push("text-success");
        break;
      case 'disconnected':
        statusClasses.push("fa-times-circle");
        statusClasses.push("text-muted");
        break;
      case 'password':
        statusClasses.push("fa-exclamation-triangle");
        statusClasses.push("text-warning");
        break;
      case 'loaded':
      default:
        statusClasses.push("fa-spinner fa-spin");
        statusClasses.push("text-primary");
        break;
    }

    if (state === 'normal') {
      if (UI.rfb.get_encrypt()) {
        msg = "Connected (encrypted)";
      } else {
        msg = "Connected (unencrypted)";
      }
    }

    // Update status icon.
    if (typeof(msg) !== 'undefined') {
      $('#statusIcon').attr("class", statusClasses.join(' '));
      $('#statusIcon').attr("data-original-title", msg);
      $('#statusIconSR').text(msg);
    }

    // Save RFB state.
    UI.rfb_state = state;

    // Invoke registered callbacks.
    UI.rfbUpdateStateCallbacks.fire(rfb, state, oldstate, msg);

    Util.Debug("<< UI.rfbOnUpdateState");
  },

  rfbOnMouseButton: function (x, y, down, bmask) {
    // Invoke registered callbacks.
    this.rfbOnMouseButtonCallbacks.fire(this.rfb, x, y, down, bmask);

    // Call the original callback.
    this.rfbOriginalOnMouseButton(x, y, down, bmask);
  },

  rfbOnMouseMove: function (x, y) {
    // Invoke registered callbacks.
    this.rfbOnMouseMoveCallbacks.fire(this.rfb, x, y);

    // Call the original callback.
    this.rfbOriginalOnMouseMove(x, y);
  },

  /****************************************************************************
   * Misc functions
   ****************************************************************************/

  appNameUpdate: function(name) {
    if (name) {
      UI.appName = name;
      document.title = name;
      $('#appName').text(name);
    }
  },

  // Gets the the size of the available viewport in the browser window.
  screenSize: function() {
    var navbar_h = ModuleMgr.isActive('HideableNavbar') ? 0 : 51;
    return {w: $(window).width(), h: $(window).height() - navbar_h };
  },

  rfbDisplayBlur: function() {
    if (!UI.rfb) return;
    UI.rfb.get_keyboard().set_focused(false);
    UI.rfb.get_mouse().set_focused(false);
  },

  rfbDisplayFocus: function() {
    if (!UI.rfb) return;
    UI.rfb.get_keyboard().set_focused(true);
    UI.rfb.get_mouse().set_focused(true);
  },

  /****************************************************************************
   * Setting manipulation
   ****************************************************************************/

  getSettingName: function(name) {
    // Name of settings provides port isolation.  This means that a setting is
    // not shared between two connections to the same host using different HTTP
    // ports.
    return "novnc-ui-" + window.location.port + "-" + name;
  },

  saveSetting: function(name, value) {
    var type = typeof value;
    switch (type) {
      case 'boolean':
      case 'string':
      case 'number':
        localStorage.setItem(UI.getSettingName(name), type + ':' + value);
        break;
      default:
        Util.Error("saveSetting: " + name + ": Unsupported value type: " + type);
        break;
    }
  },

  getSetting: function(name, defaultValue) {
    // Get setting value from local storage.
    var value = localStorage.getItem(UI.getSettingName(name));
    if (typeof value === "undefined") {
      value = null;
    }

    // Convert to value to proper type.
    if (value !== null) {
      var res = value.split(':');
      if (res.length > 1) {
        var type = res.shift();
        value = res.join(':');

        switch (type) {
          case 'boolean':
            value = (value === 'true');
            break;
          case 'string':
            break;
          case 'number':
            value = Number(value);
            break;
           default:
            Util.Error("getSetting: " + name + ": Invalid value type: " + type);
            return;
        }
      }
      else {
        Util.Error("getSetting: " + name + ": Invalid setting value format: " + value);
        value = null;
      }
    }

    // Return the setting value.
    if (value === null) {
      return (typeof defaultValue !== 'undefined') ? defaultValue : null;
    }
    else {
      return value;
    }
  },

};
