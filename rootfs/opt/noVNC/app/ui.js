/*
 * noVNC: HTML5 VNC client
 * Copyright (C) 2019 The noVNC Authors
 * Licensed under MPL 2.0 (see LICENSE.txt)
 *
 * See README.md for usage and integration instructions.
 */

import * as Log from '../core/util/logging.js';
import { isTouchDevice, isMac, isIOS, isAndroid, isChromeOS, isSafari,
         hasScrollbarGutter, dragThreshold }
    from '../core/util/browser.js';
import { setCapture, getPointerEvent } from '../core/util/events.js';
import KeyTable from "../core/input/keysym.js";
import keysyms from "../core/input/keysymdef.js";
import Keyboard from "../core/input/keyboard.js";
import RFB from "../core/rfb.js";
import * as WebUtil from "./webutil.js";
import { PCMPlayer } from "./pcm-player.min.js";
import FileManager from "./fileManager.js";
import NotificationService from "./notificationService.js";

const UI = {

    webData: null,

    connected: false,
    desktopName: "",

    statusTimeout: null,
    idleControlbarTimeout: null,
    closeControlbarTimeout: null,

    controlbarGrabbed: false,
    controlbarDrag: false,
    controlbarMouseDownClientY: 0,
    controlbarMouseDownOffsetY: 0,

    lastKeyboardinput: null,
    defaultKeyboardinputLen: 100,

    ongoingReconnect: false,
    reconnectAttempts: 0,
    reconnectCallback: null,
    reconnectPassword: null,
    reconnectPasswordFailures: 0,

    audioContext: null,

    fileManager: null,

    notificationService: null,

    async start() {

        // Initialize setting storage
        await WebUtil.initSettings();

        // Wait for the page to load
        if (document.readyState !== "interactive" && document.readyState !== "complete") {
            await new Promise((resolve, reject) => {
                document.addEventListener('DOMContentLoaded', resolve);
            });
        }

        // Load web data.
        await UI.fetchWebData();

        UI.initSettings();

        // Set page title.
        document.title = UI.webData.applicationName;
        UI.desktopName = UI.webData.applicationName;
        Array.from(document.getElementsByName('noVNC_app_name'))
            .forEach(el => el.innerText = UI.webData.applicationName);

        // Update logo image properties.
        document.getElementById('noVNC_app_logo').alt = UI.webData.applicationName + 'logo';
        document.getElementById('noVNC_app_logo').title = UI.webData.applicationName;

        // Set or hide the application version.
        if (UI.webData.applicationVersion) {
            document.getElementById('noVNC_version_app')
                .innerText = UI.webData.applicationName + ' v' + UI.webData.applicationVersion;
            document.getElementById('noVNC_version_app')
                .classList.remove("noVNC_hidden");
        }

        // Set or hide the Docker image version.
        if (UI.webData.dockerImageVersion) {
            document.getElementById('noVNC_version_docker_image')
                .innerText = 'Docker Image v' + UI.webData.dockerImageVersion;
            document.getElementById('noVNC_version_docker_image')
                .classList.remove("noVNC_hidden");
        }

        // Display the control bar footer if a version is set.
        if (UI.webData.applicationVersion || UI.webData.dockerImageVersion) {
            document.getElementById('noVNC_version_footer')
                .classList.remove("noVNC_hidden");
        }

        // Enable dark mode.
        if (UI.webData.darkMode) {
            document.documentElement.setAttribute('data-bs-theme', 'dark');
        }

        // Enable audio support.
        if (!(window.AudioContext || window.webkitAudioContext)) {
            Log.Info("Web audio not supported by browser.");
        } else if (UI.webData.audioSupport) {
            UI.audioContext = {
                audioEnabled: false,
                player: new PCMPlayer({
                    encoding: '16bitIntLE',
                    channels: 2,
                    sampleRate: 44100,
                }),
            },
            UI.addAudioHandlers();
            UI.updateLogging();
            document.getElementById('noVNC_audio_section')
                .classList.remove("noVNC_hidden");
        }

        // Web authentication support.
        if (UI.webData.webAuthSupport) {
            document.getElementById('noVNC_logout_button')
                .classList.remove("noVNC_hidden");
        }

        // Enable file manager.
        if (UI.webData.fileManager) {
            // Activate file manager button in control bar.
            UI.addFileManagerHandlers();
            document.getElementById('noVNC_file_manager_button')
                .classList.remove("noVNC_hidden");

            const host = UI.getSetting('host');
            const port = UI.getSetting('port');
            const path = UI.getSetting('filemanager_path');

            let url;
            url = UI.getSetting('encrypt') ? 'wss' : 'ws';
            url += '://' + host;
            if (port) {
                url += ':' + port;
            }
            url += '/' + window.location.pathname.substr(1) + path;

            // Initialize the file manager.
            UI.fileManager = FileManager;
            UI.fileManager.init(url);
            UI.fileManager.addEventListener('close', function() {
                UI.closeFileManager();
            });
        }

        // Enable notifications.
        if (UI.webData.notificationSupport) {
            const host = UI.getSetting('host');
            const port = UI.getSetting('port');
            const path = UI.getSetting('notification_path');

            let url;
            url = UI.getSetting('encrypt') ? 'wss' : 'ws';
            url += '://' + host;
            if (port) {
                url += ':' + port;
            }
            url += '/' + window.location.pathname.substr(1) + path;

            UI.notificationService = NotificationService;
            UI.notificationService.init(url);
        }

        // Adapt the interface for touch screen devices
        if (isTouchDevice) {
            document.documentElement.classList.add("noVNC_touch");
            // Remove the address bar
            setTimeout(() => window.scrollTo(0, 1), 100);
        }

        // Collapse settings and clipboard sections by default on small screens.
        if (window.innerHeight < 600) {
            document.getElementById('settingsCollapse')
                .classList.remove("show");
            document.getElementById('clipboardCollapse')
                .classList.remove("show");
        }
        // On touch devices, the on-screen keyboard can take a fair amount of
        // space.  So collapse settings by default if space is too tight with
        // the on-screen keyboard open.
        else if (isTouchDevice && window.innerHeight < 800) {
            document.getElementById('settingsCollapse')
                .classList.remove("show");
        }

        // Restore control bar position
        if (WebUtil.readSetting('controlbar_pos') === 'right') {
            UI.toggleControlbarSide();
        }

        UI.initFullscreen();

        // Setup event handlers
        UI.addControlbarHandlers();
        UI.addTouchSpecificHandlers();
        UI.addConnectionControlHandlers();
        UI.addClipboardHandlers();
        UI.addSettingsHandlers();
        document.getElementById("noVNC_status")
            .addEventListener('click', UI.hideStatus);

        // Setup observer to detect when all action icons are hidden.
        const mutationObserver = new MutationObserver(function (mutationsList, observer) {
            mutationsList.every(mutation => {
                if (mutation.attributeName === 'class') {
                    UI.updateActionIconsSection();
                    return false;
                }
                else {
                    return true;
                }
            })
        });
        // Observe all actions buttons.  Note that the keyboard button is hidden
        // in CSS via the 'noVNC_touch' class.  Thus, this button doesn't have
        // the 'noVNC_hidden' class.
        // mutationObserver.observe(document.getElementById('noVNC_keyboard_button'), { attributes: true });
        mutationObserver.observe(document.getElementById('noVNC_fullscreen_button'), { attributes: true });
        mutationObserver.observe(document.getElementById('noVNC_view_drag_button'), { attributes: true });
        mutationObserver.observe(document.getElementById('noVNC_file_manager_button'), { attributes: true });

        UI.updateActionIconsSection();

        // Bootstrap fallback input handler
        UI.keyboardinputReset();

        UI.updateVisualState('init');

        document.documentElement.classList.remove("noVNC_loading");

        window.addEventListener('orientationchange', function () {
            var originalBodyStyle = getComputedStyle(document.body).getPropertyValue('display');
            document.body.style.display='none';
            setTimeout(function () {
                document.body.style.display = originalBodyStyle;
            }, 10);
        });

        // Connect automatically.
        UI.connect();

        return Promise.resolve(UI.rfb);
    },

    initFullscreen() {
        // Only show the button if fullscreen is properly supported
        // Safari doesn't support alphanumerical input while in fullscreen
        // Fullscreen cannot work if we are loaded in iFrame
        const isIframe = typeof window !== 'undefined' && window.self !== window.top;
        if (!isSafari() &&
            !isIframe &&
            (document.documentElement.requestFullscreen ||
             document.documentElement.mozRequestFullScreen ||
             document.documentElement.webkitRequestFullscreen ||
             document.body.msRequestFullscreen)) {
            document.getElementById('noVNC_fullscreen_button')
                .classList.remove("noVNC_hidden");
            UI.addFullscreenHandlers();
        }
    },

    initSettings() {
        // Logging selection dropdown

        // Settings with immediate effects
        UI.initSetting('logging', 'warn');
        UI.updateLogging();

        // If port == 80 (or 443) then it won't be present and should be
        // set manually
        let port = window.location.port;
        if (!port) {
            if (window.location.protocol.substring(0, 5) == 'https') {
                port = 443;
            } else if (window.location.protocol.substring(0, 4) == 'http') {
                port = 80;
            }
        }

        // Use remote sizing by default...
        let resize = 'remote';
        if (isTouchDevice) {
            // ... unless we run on a touch device.
            resize = 'scale';
        } else if (UI.webData.applicationWindowWidth && window.innerWidth < 0.8 * UI.webData.applicationWindowWidth) {
            // ... unless the browser's window width is less than 80% of the
            // defined application's window width.
            resize = 'scale';
        } else if (UI.webData.applicationWindowHeight && window.innerHeight < 0.8 * UI.webData.applicationWindowHeight) {
            // ... unless the browser's window height is less than 80% of the
            // defined application's window height.
            resize = 'scale';
        }

        /* Populate the controls if defaults are provided in the URL */
        UI.initSetting('host', window.location.hostname);
        UI.initSetting('port', port);
        UI.initSetting('encrypt', (window.location.protocol === "https:"));
        UI.initSetting('view_clip', false);
        UI.initSetting('resize', resize);
        UI.initSetting('quality', 6);
        UI.initSetting('compression', 2);
        UI.initSetting('shared', true);
        UI.initSetting('view_only', false);
        UI.initSetting('show_dot', false);
        UI.initSetting('path', 'websockify');
        UI.initSetting('audio_path', 'websockify-audio');
        UI.initSetting('filemanager_path', 'ws-filemanager');
        UI.initSetting('notification_path', 'ws-notification');
        UI.initSetting('repeaterID', '');
        UI.initSetting('reconnect', true);
        UI.initSetting('reconnect_delay', 5000);
    },

    fetchWebData() {
        return fetch('./webdata.json')
            .then(response => {
                if (!response.ok) {
                    throw new Error(`Could not fetch web data: HTTP error: Status: ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                Log.Debug('Web data:', data);
                UI.webData = data;
            })
            .catch(error => {
                throw new Error(`Could not load web data: ${error}`);
            });
    },

    checkWebData() {
        let currentContainerInstanceUID = UI.webData.containerInstanceUID;
        UI.fetchWebData().then(() => {
            if (currentContainerInstanceUID === UI.webData.containerInstanceUID) {
                Log.Error("Container instance UID remained the same.");
            } else {
                Log.Error("Container instance UID changed. Reloading page.");
                window.location.reload();
            }
        }).catch((e) => {
            Log.Error(e);
        });
    },

/* ------^-------
*     /INIT
* ==============
* EVENT HANDLERS
* ------v------*/

    addControlbarHandlers() {
        document.getElementById("noVNC_control_bar")
            .addEventListener('mousemove', () => { UI.activateControlbar(); clearTimeout(UI.idleControlbarTimeout); });
        document.getElementById("noVNC_control_bar")
            .addEventListener('mouseleave', UI.activateControlbar);

        document.getElementById("noVNC_control_bar")
            .addEventListener('mouseup', () => { UI.activateControlbar(); clearTimeout(UI.idleControlbarTimeout); });
        document.getElementById("noVNC_control_bar")
            .addEventListener('mousedown', () => { UI.activateControlbar(); clearTimeout(UI.idleControlbarTimeout); });
        document.getElementById("noVNC_control_bar")
            .addEventListener('keydown', UI.activateControlbar);

        document.getElementById("noVNC_control_bar")
            .addEventListener('mousedown', UI.keepControlbar);
        document.getElementById("noVNC_control_bar")
            .addEventListener('keydown', UI.keepControlbar);

        document.getElementById("noVNC_view_drag_button")
            .addEventListener('click', UI.toggleViewDrag);

        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('mousedown', UI.controlbarHandleMouseDown);
        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('mouseup', UI.controlbarHandleMouseUp);
        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('mousemove', UI.dragControlbarHandle);
        // resize events aren't available for elements
        window.addEventListener('resize', UI.updateControlbarHandle);
    },

    addTouchSpecificHandlers() {
        document.getElementById("noVNC_keyboard_button")
            .addEventListener('click', UI.toggleVirtualKeyboard);

        UI.touchKeyboard = new Keyboard(document.getElementById('noVNC_keyboardinput'));
        UI.touchKeyboard.onkeyevent = UI.keyEvent;
        UI.touchKeyboard.grab();
        document.getElementById("noVNC_keyboardinput")
            .addEventListener('input', UI.keyInput);
        document.getElementById("noVNC_keyboardinput")
            .addEventListener('focus', UI.onfocusVirtualKeyboard);
        document.getElementById("noVNC_keyboardinput")
            .addEventListener('blur', UI.onblurVirtualKeyboard);
        document.getElementById("noVNC_keyboardinput")
            .addEventListener('submit', () => false);

        document.documentElement
            .addEventListener('mousedown', UI.keepVirtualKeyboard, true);

        document.getElementById("noVNC_control_bar")
            .addEventListener('touchstart', UI.activateControlbar);
        document.getElementById("noVNC_control_bar")
            .addEventListener('touchmove', UI.activateControlbar);
        document.getElementById("noVNC_control_bar")
            .addEventListener('touchend', UI.activateControlbar);
        document.getElementById("noVNC_control_bar")
            .addEventListener('input', UI.activateControlbar);

        document.getElementById("noVNC_control_bar")
            .addEventListener('touchstart', UI.keepControlbar);
        document.getElementById("noVNC_control_bar")
            .addEventListener('input', UI.keepControlbar);

        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('touchstart', UI.controlbarHandleMouseDown);
        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('touchend', UI.controlbarHandleMouseUp);
        document.getElementById("noVNC_control_bar_handle")
            .addEventListener('touchmove', UI.dragControlbarHandle);
    },

    addConnectionControlHandlers() {
        document.getElementById("noVNC_credentials_button")
            .addEventListener('click', UI.setCredentials);
    },

    addClipboardHandlers() {
        document.getElementById("noVNC_clipboard_text")
            .addEventListener('input', UI.clipboardSend);
        document.getElementById("noVNC_clipboard_clear_button")
            .addEventListener('click', UI.clipboardClear);
    },

    // Add a call to save settings when the element changes,
    // unless the optional parameter changeFunc is used instead.
    addSettingChangeHandler(name, changeFunc) {
        const settingElem = document.getElementById("noVNC_setting_" + name);
        if (changeFunc === undefined) {
            changeFunc = () => UI.saveSetting(name);
        }
        settingElem.addEventListener('change', changeFunc);
    },

    addSettingsHandlers() {
        UI.addSettingChangeHandler('resize');
        UI.addSettingChangeHandler('resize', UI.applyResizeMode);
        UI.addSettingChangeHandler('resize', UI.updateViewClip);
        UI.addSettingChangeHandler('quality');
        UI.addSettingChangeHandler('quality', UI.updateQuality);
        UI.addSettingChangeHandler('compression');
        UI.addSettingChangeHandler('compression', UI.updateCompression);
        UI.addSettingChangeHandler('view_clip');
        UI.addSettingChangeHandler('view_clip', UI.updateViewClip);
        UI.addSettingChangeHandler('logging');
        UI.addSettingChangeHandler('logging', UI.updateLogging);
        UI.addSettingChangeHandler('audio_volume');
        UI.addSettingChangeHandler('audio_volume', UI.updateAudioVolume);
    },

    addFullscreenHandlers() {
        document.getElementById("noVNC_fullscreen_button")
            .addEventListener('click', UI.toggleFullscreen);

        window.addEventListener('fullscreenchange', UI.updateFullscreenButton);
        window.addEventListener('mozfullscreenchange', UI.updateFullscreenButton);
        window.addEventListener('webkitfullscreenchange', UI.updateFullscreenButton);
        window.addEventListener('msfullscreenchange', UI.updateFullscreenButton);
    },

    addAudioHandlers() {
        document.getElementById("noVNC_audio_button")
            .addEventListener('click', UI.toggleAudio);
    },

    addFileManagerHandlers() {
        document.getElementById("noVNC_file_manager_button")
            .addEventListener('click', UI.toggleFileManager);
    },

/* ------^-------
 * /EVENT HANDLERS
 * ==============
 *     VISUAL
 * ------v------*/

    // Disable/enable controls depending on connection state
    updateVisualState(state) {

        // While reconnecting, inhibit some visual state changes.
        if (UI.ongoingReconnect) {
            switch (state) {
                case 'connecting':
                    return;
                case 'reconnecting':
                    if (document.documentElement.classList.contains("noVNC_reconnecting")) {
                        return;
                    } else {
                        break;
                    }
                case 'disconnected':
                    return;
                case 'connected':
                    break;
                default:
                    Log.Error("Unexpected state while reconnecting: " + state);
            }
        }

        document.documentElement.classList.remove("noVNC_connecting");
        document.documentElement.classList.remove("noVNC_connected");
        document.documentElement.classList.remove("noVNC_disconnecting");
        document.documentElement.classList.remove("noVNC_reconnecting");

        const transitionElem = document.getElementById("noVNC_transition_text");
        switch (state) {
            case 'init':
                break;
            case 'connecting':
                transitionElem.textContent = "Connecting...";
                document.documentElement.classList.add("noVNC_connecting");
                break;
            case 'connected':
                document.documentElement.classList.add("noVNC_connected");
                break;
            case 'disconnecting':
                transitionElem.textContent = "Disconnecting...";
                document.documentElement.classList.add("noVNC_disconnecting");
                break;
            case 'disconnected':
                break;
            case 'reconnecting':
                transitionElem.textContent = "Reconnecting...";
                document.documentElement.classList.add("noVNC_reconnecting");
                break;
            default:
                Log.Error("Invalid visual state: " + state);
                UI.showStatus("Internal error", 'error');
                return;
        }

        if (UI.connected) {
            UI.updateViewClip();

            document.getElementById('noVNC_control_bar_anchor')
                .classList.remove("noVNC_hidden");

            // On first run, show the control bar and automatically hide it
            // after 2 seconds.
            if (WebUtil.readSetting('first_run') != 'false') {
                UI.openControlbar();

                // Hide the control bar after 2 seconds
                UI.closeControlbarTimeout = setTimeout(UI.closeControlbar, 2000);
                WebUtil.writeSetting('first_run', 'false');
            }
        } else {
            UI.closeControlbar();
            document.getElementById('noVNC_control_bar_anchor')
                .classList.add("noVNC_hidden");
        }

        // State change closes dialogs as they may not be relevant
        // anymore
        document.getElementById('noVNC_credentials_dlg')
            .classList.remove('noVNC_open');
    },

    showStatus(text, statusType, time, force) {
        const statusElem = document.getElementById('noVNC_status');

        if (typeof statusType === 'undefined') {
            statusType = 'normal';
        }

        // Do not change status messages while reconnecting.
        if (!force && UI.ongoingReconnect) {
            return;
        }

        // Don't overwrite more severe visible statuses and never
        // errors. Only shows the first error.
        if (!force && statusElem.classList.contains("noVNC_open")) {
            if (statusElem.classList.contains("noVNC_status_error")) {
                return;
            }
            if (statusElem.classList.contains("noVNC_status_warn") &&
                statusType === 'normal') {
                return;
            }
        }

        clearTimeout(UI.statusTimeout);

        switch (statusType) {
            case 'error':
                statusElem.classList.remove("noVNC_status_warn");
                statusElem.classList.remove("noVNC_status_normal");
                statusElem.classList.add("noVNC_status_error");
                break;
            case 'warning':
            case 'warn':
                statusElem.classList.remove("noVNC_status_error");
                statusElem.classList.remove("noVNC_status_normal");
                statusElem.classList.add("noVNC_status_warn");
                break;
            case 'normal':
            case 'info':
            default:
                statusElem.classList.remove("noVNC_status_error");
                statusElem.classList.remove("noVNC_status_warn");
                statusElem.classList.add("noVNC_status_normal");
                break;
        }

        statusElem.textContent = text;
        statusElem.classList.add("noVNC_open");

        // If no time was specified, show the status for 1.5 seconds
        if (typeof time === 'undefined') {
            time = 1500;
        }

        // Error messages do not timeout
        if (statusType !== 'error') {
            UI.statusTimeout = window.setTimeout(UI.hideStatus, time);
        }
    },

    hideStatus() {
        clearTimeout(UI.statusTimeout);
        document.getElementById('noVNC_status').classList.remove("noVNC_open");
    },

    activateControlbar(event) {
        clearTimeout(UI.idleControlbarTimeout);
        // We manipulate the anchor instead of the actual control
        // bar in order to avoid creating new a stacking group
        document.getElementById('noVNC_control_bar_anchor')
            .classList.remove("noVNC_idle");
        UI.idleControlbarTimeout = window.setTimeout(UI.idleControlbar, 2000);
    },

    idleControlbar() {
        // Don't fade if a child of the control bar has focus
        if (document.getElementById('noVNC_control_bar')
            .contains(document.activeElement) && document.hasFocus()) {
            UI.activateControlbar();
            return;
        }

        document.getElementById('noVNC_control_bar_anchor')
            .classList.add("noVNC_idle");
    },

    keepControlbar() {
        clearTimeout(UI.closeControlbarTimeout);
        UI.closeControlbarTimeout = null
    },

    openControlbar() {
        document.getElementById('noVNC_control_bar')
            .classList.add("noVNC_open");

        // Set focus on the clipboard text box, if it is visible from the
        // the control menu.
        // NOTE: We don't want this behavior on touch device, because this will
        // brings up the virtual keyboard, which might not be wanted.
        if (!isTouchDevice && document.getElementById('clipboardCollapse')
            .classList.contains("show")) {
            document.getElementById('noVNC_clipboard_text').focus();
        }
    },

    closeControlbar() {
        //UI.closeAllPanels();
        document.getElementById('noVNC_control_bar')
            .classList.remove("noVNC_open");
        // On touch device, we don't want to change the focus if the virtual
        // keyboard is active (we want to keep it open and changing focus will
        // close it).
        if (UI.rfb && (!isTouchDevice || document.activeElement != document.getElementById('noVNC_keyboardinput'))) {
            UI.rfb.focus();
        }
        UI.closeControlbarTimeout = null
    },

    toggleControlbar() {
        if (document.getElementById('noVNC_control_bar')
            .classList.contains("noVNC_open")) {
            UI.closeControlbar();
        } else {
            UI.openControlbar();
        }
    },

    toggleControlbarSide() {
        // Temporarily disable animation, if bar is displayed, to avoid weird
        // movement. The transitionend-event will not fire when display=none.
        /*
        const bar = document.getElementById('noVNC_control_bar');
        const barDisplayStyle = window.getComputedStyle(bar).display;
        if (barDisplayStyle !== 'none') {
            bar.style.transitionDuration = '0s';
            bar.addEventListener('transitionend', () => bar.style.transitionDuration = '');
        }
        */

        const anchor = document.getElementById('noVNC_control_bar_anchor');
        const control_bar = document.getElementById("noVNC_control_bar")
        if (anchor.classList.contains("noVNC_right")) {
            WebUtil.writeSetting('controlbar_pos', 'left');
            anchor.classList.remove("noVNC_right");
            control_bar.classList.remove("flex-row-reverse");
        } else {
            WebUtil.writeSetting('controlbar_pos', 'right');
            anchor.classList.add("noVNC_right");
            control_bar.classList.add("flex-row-reverse");
        }

        // Consider this a movement of the handle
        UI.controlbarDrag = true;

        // The user has "followed" hint, let's hide it until the next drag
        UI.showControlbarHint(false);
    },

    showControlbarHint(show) {
        const hint = document.getElementById('noVNC_control_bar_hint');
        if (show) {
            hint.classList.add("noVNC_active");
        } else {
            hint.classList.remove("noVNC_active");
        }
    },

    dragControlbarHandle(e) {
        if (!UI.controlbarGrabbed) return;

        const ptr = getPointerEvent(e);

        const anchor = document.getElementById('noVNC_control_bar_anchor');
        if (ptr.clientX < (window.innerWidth * 0.1)) {
            if (anchor.classList.contains("noVNC_right")) {
                UI.toggleControlbarSide();
            }
        } else if (ptr.clientX > (window.innerWidth * 0.9)) {
            if (!anchor.classList.contains("noVNC_right")) {
                UI.toggleControlbarSide();
            }
        }

        if (!UI.controlbarDrag) {
            const dragDistance = Math.abs(ptr.clientY - UI.controlbarMouseDownClientY);

            if (dragDistance < dragThreshold) return;

            UI.controlbarDrag = true;
        }

        const eventY = ptr.clientY - UI.controlbarMouseDownOffsetY;

        UI.moveControlbarHandle(eventY);

        e.preventDefault();
        e.stopPropagation();
        UI.keepControlbar();
        UI.activateControlbar();
    },

    // Move the handle but don't allow any position outside the bounds
    moveControlbarHandle(viewportRelativeY) {
        const handle = document.getElementById("noVNC_control_bar_handle");
        const handleHeight = handle.getBoundingClientRect().height;
        const controlbarBounds = document.getElementById("noVNC_control_bar")
            .getBoundingClientRect();
        const margin = 10;

        // These heights need to be non-zero for the below logic to work
        if (handleHeight === 0 || controlbarBounds.height === 0) {
            return;
        }

        let newY = viewportRelativeY;

        // Check if the coordinates are outside the control bar
        if (newY < controlbarBounds.top + margin) {
            // Force coordinates to be below the top of the control bar
            newY = controlbarBounds.top + margin;

        } else if (newY > controlbarBounds.top +
                   controlbarBounds.height - handleHeight - margin) {
            // Force coordinates to be above the bottom of the control bar
            newY = controlbarBounds.top +
                controlbarBounds.height - handleHeight - margin;
        }

        // Corner case: control bar too small for stable position
        if (controlbarBounds.height < (handleHeight + margin * 2)) {
            newY = controlbarBounds.top +
                (controlbarBounds.height - handleHeight) / 2;
        }

        // The transform needs coordinates that are relative to the parent
        const parentRelativeY = newY - controlbarBounds.top;
        handle.style.transform = "translateY(" + parentRelativeY + "px)";
    },

    updateControlbarHandle() {
        // Since the control bar is fixed on the viewport and not the page,
        // the move function expects coordinates relative the the viewport.
        const handle = document.getElementById("noVNC_control_bar_handle");
        const handleBounds = handle.getBoundingClientRect();
        UI.moveControlbarHandle(handleBounds.top);
    },

    controlbarHandleMouseUp(e) {
        if ((e.type == "mouseup") && (e.button != 0)) return;

        // mouseup and mousedown on the same place toggles the controlbar
        if (UI.controlbarGrabbed && !UI.controlbarDrag) {
            UI.toggleControlbar();
            e.preventDefault();
            e.stopPropagation();
            UI.keepControlbar();
            UI.activateControlbar();
        }
        UI.controlbarGrabbed = false;
        UI.showControlbarHint(false);
    },

    controlbarHandleMouseDown(e) {
        if ((e.type == "mousedown") && (e.button != 0)) return;

        const ptr = getPointerEvent(e);

        const handle = document.getElementById("noVNC_control_bar_handle");
        const bounds = handle.getBoundingClientRect();

        // Touch events have implicit capture
        if (e.type === "mousedown") {
            setCapture(handle);
        }

        UI.controlbarGrabbed = true;
        UI.controlbarDrag = false;

        UI.showControlbarHint(true);

        UI.controlbarMouseDownClientY = ptr.clientY;
        UI.controlbarMouseDownOffsetY = ptr.clientY - bounds.top;
        e.preventDefault();
        e.stopPropagation();
        UI.keepControlbar();
        UI.activateControlbar();
    },

    updateActionIconsSection(mutationsList, observer) {
        // Hide the action icons section if all icons are hidden.
        // NOTE: The keyboard button is hidden in CSS via the 'noVNC_touch'
        // class.
        if (!document.documentElement.classList.contains('noVNC_touch') &&
            document.getElementById('noVNC_fullscreen_button').classList.contains('noVNC_hidden') &&
            document.getElementById('noVNC_view_drag_button').classList.contains('noVNC_hidden') &&
            document.getElementById('noVNC_file_manager_button').classList.contains('noVNC_hidden')) {
            // All icons hidden: also hide the section.
            document.getElementById('noVNC_action_icons_section').classList.add('noVNC_hidden');
        }
        else {
            document.getElementById('noVNC_action_icons_section').classList.remove('noVNC_hidden');
        }
    },

/* ------^-------
 *    /VISUAL
 * ==============
 *    SETTINGS
 * ------v------*/

    // Initial page load read/initialization of settings
    initSetting(name, defVal) {
        // Check Query string followed by cookie
        let val = WebUtil.getConfigVar(name);
        if (val === null) {
            val = WebUtil.readSetting(name, defVal);
        }
        WebUtil.setSetting(name, val);
        if (document.getElementById('noVNC_setting_' + name) !== null) {
            UI.updateSetting(name);
        }
        return val;
    },

    // Set the new value, update and disable form control setting
    forceSetting(name, val) {
        WebUtil.setSetting(name, val);
        UI.updateSetting(name);
        UI.disableSetting(name);
    },

    // Update cookie and form control setting. If value is not set, then
    // updates from control to current cookie setting.
    updateSetting(name) {

        // Update the settings control
        let value = UI.getSetting(name);

        const ctrl = document.getElementById('noVNC_setting_' + name);
        if (ctrl.type === 'checkbox') {
            ctrl.checked = value;

        } else if (typeof ctrl.options !== 'undefined') {
            for (let i = 0; i < ctrl.options.length; i += 1) {
                if (ctrl.options[i].value === value) {
                    ctrl.selectedIndex = i;
                    break;
                }
            }
        } else {
            ctrl.value = value;
        }
    },

    // Save control setting to cookie
    saveSetting(name) {
        const ctrl = document.getElementById('noVNC_setting_' + name);
        let val;
        if (ctrl.type === 'checkbox') {
            val = ctrl.checked;
        } else if (typeof ctrl.options !== 'undefined') {
            val = ctrl.options[ctrl.selectedIndex].value;
        } else {
            val = ctrl.value;
        }
        WebUtil.writeSetting(name, val);
        //Log.Debug("Setting saved '" + name + "=" + val + "'");
        return val;
    },

    // Read form control compatible setting from cookie
    getSetting(name) {
        const ctrl = document.getElementById('noVNC_setting_' + name);
        let val = WebUtil.readSetting(name);
        if (typeof val !== 'undefined' && val !== null && ctrl !== null && ctrl.type === 'checkbox') {
            if (val.toString().toLowerCase() in {'0': 1, 'no': 1, 'false': 1}) {
                val = false;
            } else {
                val = true;
            }
        }
        return val;
    },

    // These helpers compensate for the lack of parent-selectors and
    // previous-sibling-selectors in CSS which are needed when we want to
    // disable the labels that belong to disabled input elements.
    disableSetting(name) {
        const ctrl = document.getElementById('noVNC_setting_' + name);
        ctrl.disabled = true;
        //ctrl.label.classList.add('noVNC_disabled');
    },

    enableSetting(name) {
        const ctrl = document.getElementById('noVNC_setting_' + name);
        ctrl.disabled = false;
        //ctrl.label.classList.remove('noVNC_disabled');
    },

/* ------^-------
 *   /SETTINGS
 * ==============
 *   CLIPBOARD
 * ------v------*/

    clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        Log.Debug("<< UI.clipboardReceive");
    },

    clipboardClear() {
        document.getElementById('noVNC_clipboard_text').value = "";
        UI.rfb.clipboardPasteFrom("");
    },

    clipboardSend() {
        const text = document.getElementById('noVNC_clipboard_text').value;
        Log.Debug(">> UI.clipboardSend: " + text.substr(0, 40) + "...");
        UI.rfb.clipboardPasteFrom(text);
        Log.Debug("<< UI.clipboardSend");
    },

/* ------^-------
 *  /CLIPBOARD
 * ==============
 *  CONNECTION
 * ------v------*/

    connect(event, password) {

        // Ignore when rfb already exists
        if (typeof UI.rfb !== 'undefined') {
            return;
        }

        const host = UI.getSetting('host');
        const port = UI.getSetting('port');
        const path = UI.getSetting('path');

        if (typeof password === 'undefined') {
            password = WebUtil.getConfigVar('password');
            UI.reconnectPassword = password;
        }

        if (password === null) {
            password = undefined;
        }

        if (!UI.ongoingReconnect) {
            UI.hideStatus();
        }

        UI.updateVisualState('connecting');

        let url;

        url = UI.getSetting('encrypt') ? 'wss' : 'ws';

        url += '://' + host;
        if (port) {
            url += ':' + port;
        }
        url += '/' + window.location.pathname.substr(1) + path;

        try {
            UI.rfb = new RFB(document.getElementById('noVNC_container'), url,
                             { shared: UI.getSetting('shared'),
                               repeaterID: UI.getSetting('repeaterID'),
                               credentials: { password: password },
                               wsProtocols: ['binary']});
        } catch (exc) {
            Log.Error("Failed to connect to server: " + exc);
            UI.updateVisualState('disconnected');
            UI.showStatus("Failed to connect to server: " + exc, 'error');
            return;
        }

        UI.rfb.addEventListener("connect", UI.connectFinished);
        UI.rfb.addEventListener("disconnect", UI.disconnectFinished);
        UI.rfb.addEventListener("credentialsrequired", UI.credentials);
        UI.rfb.addEventListener("securityfailure", UI.securityFailed);
        UI.rfb.addEventListener("clipboard", UI.clipboardReceive);
        UI.rfb.addEventListener("desktopname", UI.updateDesktopName);
        UI.rfb.clipViewport = UI.getSetting('view_clip');
        UI.rfb.scaleViewport = UI.getSetting('resize') === 'scale';
        UI.rfb.resizeSession = UI.getSetting('resize') === 'remote';
        UI.rfb.qualityLevel = parseInt(UI.getSetting('quality'));
        UI.rfb.compressionLevel = parseInt(UI.getSetting('compression'));
        UI.rfb.showDotCursor = UI.getSetting('show_dot');

        // Automatically close the control bar when RFB gets focus.
        UI.rfb._canvas.addEventListener('focus', () => {
            if (UI.closeControlbarTimeout == null &&
                document.getElementById('noVNC_control_bar').classList.contains("noVNC_open")) {
                UI.closeControlbar();
            }
        });

        UI.updateViewOnly(); // requires UI.rfb
    },

    // Called from timer.
    reconnect() {
        UI.reconnectAttempts++;
        UI.reconnectCallback = null;
        if (UI.webData.webAuthSupport) {
            // When web authentication is enabled, reload the page when
            // connectivity is re-established. This allows to return to the
            // login page, instead of being stuck with the "reconnecting"
            // message because the WebSocket connection is denied.
            fetch('./webdata.json', { method: 'HEAD' })
                .then(response => {
                    Log.Debug(`Connectivity test result: HTTP status ${response.status}`)
                    window.location.reload();
                    return;
                })
                .catch(error => {
                    Log.Debug("Connectivity test failed: " + error)
                    const delay = parseInt(UI.getSetting('reconnect_delay'));
                    UI.reconnectCallback = setTimeout(UI.reconnect, delay);
                });
        } else {
            UI.connect(null, UI.reconnectPassword);
        }
    },

    connectFinished(e) {
        UI.connected = true;
        UI.ongoingReconnect = false;
        UI.reconnectPasswordFailures = 0;

        // Now that we re-gained connectivity, make sure web data is still
        // up-to-date.
        if (UI.reconnectAttempts > 0) {
            UI.checkWebData();
        }

        let msg;
        if (UI.getSetting('encrypt')) {
            msg = UI.desktopName + " - Connected (encrypted)";
        } else {
            msg = UI.desktopName + " - Connected (unencrypted)";
        }
        UI.showStatus(msg, 'normal', 2500, true);
        UI.updateVisualState('connected');

        // Start desktop notification.
        if (UI.notificationService) {
            UI.notificationService.start();
        }

        // Do this last because it can only be used on rendered elements
        UI.rfb.focus();
    },

    disconnectFinished(e) {
        const wasConnected = UI.connected;

        // This variable is ideally set when disconnection starts, but
        // when the disconnection isn't clean or if it is initiated by
        // the server, we need to do it here as well since
        // UI.disconnect() won't be used in those cases.
        UI.connected = false;

        UI.rfb = undefined;

        UI.showStatus(UI.desktopName + " - Disconnected", 'error');

        // If reconnecting is allowed process it now
        if (UI.getSetting('reconnect', false) === true) {
            UI.ongoingReconnect = true;
            UI.updateVisualState('reconnecting');

            const delay = parseInt(UI.getSetting('reconnect_delay'));
            UI.reconnectCallback = setTimeout(UI.reconnect, delay);
        } else {
            UI.ongoingReconnect = false;
            UI.updateVisualState('disconnected');
        }

        UI.closeControlbar()
        UI.closeFileManager()

        // Make sure audio is also stopped.
        if (UI.audioContext) {
            UI.audioContext.audioEnabled = false;
            UI.updateAudio();
        }

        // Make sure to stop desktop notification.
        if (UI.notificationService) {
            UI.notificationService.stop();
        }
    },

    securityFailed(e) {
        let msg = "";
        // On security failures we might get a string with a reason
        // directly from the server. Note that we can't control if
        // this string is translated or not.
        if ('reason' in e.detail) {
            msg = "New connection has been rejected: " +
                e.detail.reason;
        } else {
            msg = "New connection has been rejected";
        }

        // Clear the saved password for reconnect: reconnecting with the same invalid
        // credentials won't help.
        UI.reconnectPassword = null;
        UI.reconnectPasswordFailures++;

        if (UI.ongoingReconnect) {
            UI.showStatus(msg, 'error', undefined, UI.reconnectPasswordFailures > 1);
        } else {
            UI.showStatus(msg, 'error');
        }
    },

/* ------^-------
 *  /CONNECTION
 * ==============
 *   PASSWORD
 * ------v------*/

    credentials(e) {
        // FIXME: handle more types

        document.getElementById("noVNC_username_block").classList.remove("noVNC_hidden");
        document.getElementById("noVNC_password_block").classList.remove("noVNC_hidden");

        let inputFocus = "none";
        if (e.detail.types.indexOf("username") === -1) {
            document.getElementById("noVNC_username_block").classList.add("noVNC_hidden");
        } else {
            inputFocus = inputFocus === "none" ? "noVNC_username_input" : inputFocus;
        }
        if (e.detail.types.indexOf("password") === -1) {
            document.getElementById("noVNC_password_block").classList.add("noVNC_hidden");
        } else {
            inputFocus = inputFocus === "none" ? "noVNC_password_input" : inputFocus;
        }
        document.getElementById('noVNC_credentials_dlg')
            .classList.add('noVNC_open');

        setTimeout(() => document
            .getElementById(inputFocus).focus(), 100);

        Log.Warn("Server asked for credentials");
        UI.showStatus("Credentials are required", "warning", 3000, true);
    },

    setCredentials(e) {
        // Prevent actually submitting the form
        e.preventDefault();

        let inputElemUsername = document.getElementById('noVNC_username_input');
        const username = inputElemUsername.value;

        let inputElemPassword = document.getElementById('noVNC_password_input');
        const password = inputElemPassword.value;
        // Clear the input after reading the password
        inputElemPassword.value = "";

        UI.rfb.sendCredentials({ username: username, password: password });
        UI.reconnectPassword = password;
        document.getElementById('noVNC_credentials_dlg')
            .classList.remove('noVNC_open');
    },

/* ------^-------
 *  /PASSWORD
 * ==============
 *   FULLSCREEN
 * ------v------*/

    toggleFullscreen() {
        if (document.fullscreenElement || // alternative standard method
            document.mozFullScreenElement || // currently working methods
            document.webkitFullscreenElement ||
            document.msFullscreenElement) {
            if (document.exitFullscreen) {
                document.exitFullscreen();
            } else if (document.mozCancelFullScreen) {
                document.mozCancelFullScreen();
            } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
            } else if (document.msExitFullscreen) {
                document.msExitFullscreen();
            }
        } else {
            if (document.documentElement.requestFullscreen) {
                document.documentElement.requestFullscreen();
            } else if (document.documentElement.mozRequestFullScreen) {
                document.documentElement.mozRequestFullScreen();
            } else if (document.documentElement.webkitRequestFullscreen) {
                document.documentElement.webkitRequestFullscreen(Element.ALLOW_KEYBOARD_INPUT);
            } else if (document.body.msRequestFullscreen) {
                document.body.msRequestFullscreen();
            }
        }
        UI.updateFullscreenButton();
    },

    updateFullscreenButton() {
        if (document.fullscreenElement || // alternative standard method
            document.mozFullScreenElement || // currently working methods
            document.webkitFullscreenElement ||
            document.msFullscreenElement ) {
            document.getElementById('noVNC_fullscreen_button')
                .classList.add("noVNC_selected");
        } else {
            document.getElementById('noVNC_fullscreen_button')
                .classList.remove("noVNC_selected");
        }
    },

/* ------^-------
 *  /FULLSCREEN
 * ==============
 *     RESIZE
 * ------v------*/

    // Apply remote resizing or local scaling
    applyResizeMode() {
        if (!UI.rfb) return;

        UI.rfb.scaleViewport = UI.getSetting('resize') === 'scale';
        UI.rfb.resizeSession = UI.getSetting('resize') === 'remote';
    },

/* ------^-------
 *    /RESIZE
 * ==============
 * VIEW CLIPPING
 * ------v------*/

    // Update viewport clipping property for the connection. The normal
    // case is to get the value from the setting. There are special cases
    // for when the viewport is scaled or when a touch device is used.
    updateViewClip() {
        if (!UI.rfb) return;

        let resize_val = UI.getSetting('resize')
        const scaling = resize_val === 'scale' || resize_val === 'remote';

        // Some platforms have overlay scrollbars that are difficult
        // to use in our case, which means we have to force panning
        // FIXME: Working scrollbars can still be annoying to use with
        //        touch, so we should ideally be able to have both
        //        panning and scrollbars at the same time

        let brokenScrollbars = false;

        if (!hasScrollbarGutter) {
            if (isIOS() || isAndroid() || isMac() || isChromeOS()) {
                brokenScrollbars = true;
            }
        }

        if (scaling) {
            // Can't be clipping if viewport is scaled to fit
            UI.forceSetting('view_clip', false);
            UI.rfb.clipViewport  = false;
        } else if (brokenScrollbars) {
            // Some platforms have scrollbars that are difficult
            // to use in our case, so we always use our own panning
            UI.forceSetting('view_clip', true);
            UI.rfb.clipViewport = true;
        } else {
            UI.enableSetting('view_clip');
            UI.rfb.clipViewport = UI.getSetting('view_clip');
        }

        // Changing the viewport may change the state of
        // the dragging button
        UI.updateViewDrag();
    },

/* ------^-------
 * /VIEW CLIPPING
 * ==============
 *    VIEWDRAG
 * ------v------*/

    toggleViewDrag() {
        if (!UI.rfb) return;

        UI.rfb.dragViewport = !UI.rfb.dragViewport;
        UI.updateViewDrag();
    },

    updateViewDrag() {
        if (!UI.connected) return;

        const viewDragButton = document.getElementById('noVNC_view_drag_button');

        if ((!UI.rfb.clipViewport || !UI.rfb.clippingViewport) &&
            UI.rfb.dragViewport) {
            // We are no longer clipping the viewport. Make sure
            // viewport drag isn't active when it can't be used.
            UI.rfb.dragViewport = false;
        }

        if (UI.rfb.dragViewport) {
            viewDragButton.classList.add("noVNC_selected");
        } else {
            viewDragButton.classList.remove("noVNC_selected");
        }

        if (UI.rfb.clipViewport) {
            viewDragButton.classList.remove("noVNC_hidden");
        } else {
            viewDragButton.classList.add("noVNC_hidden");
        }

        viewDragButton.disabled = !UI.rfb.clippingViewport;
    },

/* ------^-------
 *   /VIEWDRAG
 * ==============
 *    QUALITY
 * ------v------*/

    updateQuality() {
        if (!UI.rfb) return;

        UI.rfb.qualityLevel = parseInt(UI.getSetting('quality'));
    },

/* ------^-------
 *   /QUALITY
 * ==============
 *  COMPRESSION
 * ------v------*/

    updateCompression() {
        if (!UI.rfb) return;

        UI.rfb.compressionLevel = parseInt(UI.getSetting('compression'));
    },

/* ------^-------
 *  /COMPRESSION
 * ==============
 *    KEYBOARD
 * ------v------*/

    showVirtualKeyboard() {
        if (!isTouchDevice) return;

        const input = document.getElementById('noVNC_keyboardinput');

        if (document.activeElement == input) return;

        input.focus();

        try {
            const l = input.value.length;
            // Move the caret to the end
            input.setSelectionRange(l, l);
        } catch (err) {
            // setSelectionRange is undefined in Google Chrome
        }
    },

    hideVirtualKeyboard() {
        if (!isTouchDevice) return;

        const input = document.getElementById('noVNC_keyboardinput');

        if (document.activeElement != input) return;

        input.blur();
    },

    toggleVirtualKeyboard() {
        if (document.getElementById('noVNC_keyboard_button')
            .classList.contains("noVNC_selected")) {
            UI.hideVirtualKeyboard();
        } else {
            UI.showVirtualKeyboard();
        }
    },

    onfocusVirtualKeyboard(event) {
        document.getElementById('noVNC_keyboard_button')
            .classList.add("noVNC_selected");
        if (UI.rfb) {
            UI.rfb.focusOnClick = false;
        }
    },

    onblurVirtualKeyboard(event) {
        document.getElementById('noVNC_keyboard_button')
            .classList.remove("noVNC_selected");
        if (UI.rfb) {
            UI.rfb.focusOnClick = true;
        }
    },

    keepVirtualKeyboard(event) {
        const input = document.getElementById('noVNC_keyboardinput');

        // Only prevent focus change if the virtual keyboard is active
        if (document.activeElement != input) {
            return;
        }

        // Only allow focus to move to other elements that need
        // focus to function properly
        if (event.target.form !== undefined) {
            switch (event.target.type) {
                case 'text':
                case 'email':
                case 'search':
                case 'password':
                case 'tel':
                case 'url':
                case 'textarea':
                case 'select-one':
                case 'select-multiple':
                    return;
            }
        }

        event.preventDefault();
    },

    keyboardinputReset() {
        const kbi = document.getElementById('noVNC_keyboardinput');
        kbi.value = new Array(UI.defaultKeyboardinputLen).join("_");
        UI.lastKeyboardinput = kbi.value;
    },

    keyEvent(keysym, code, down) {
        if (!UI.rfb) return;

        UI.rfb.sendKey(keysym, code, down);
    },

    // When normal keyboard events are left uncought, use the input events from
    // the keyboardinput element instead and generate the corresponding key events.
    // This code is required since some browsers on Android are inconsistent in
    // sending keyCodes in the normal keyboard events when using on screen keyboards.
    keyInput(event) {

        if (!UI.rfb) return;

        const newValue = event.target.value;

        if (!UI.lastKeyboardinput) {
            UI.keyboardinputReset();
        }
        const oldValue = UI.lastKeyboardinput;

        let newLen;
        try {
            // Try to check caret position since whitespace at the end
            // will not be considered by value.length in some browsers
            newLen = Math.max(event.target.selectionStart, newValue.length);
        } catch (err) {
            // selectionStart is undefined in Google Chrome
            newLen = newValue.length;
        }
        const oldLen = oldValue.length;

        let inputs = newLen - oldLen;
        let backspaces = inputs < 0 ? -inputs : 0;

        // Compare the old string with the new to account for
        // text-corrections or other input that modify existing text
        for (let i = 0; i < Math.min(oldLen, newLen); i++) {
            if (newValue.charAt(i) != oldValue.charAt(i)) {
                inputs = newLen - i;
                backspaces = oldLen - i;
                break;
            }
        }

        // Send the key events
        for (let i = 0; i < backspaces; i++) {
            UI.rfb.sendKey(KeyTable.XK_BackSpace, "Backspace");
        }
        for (let i = newLen - inputs; i < newLen; i++) {
            UI.rfb.sendKey(keysyms.lookup(newValue.charCodeAt(i)));
        }

        // Control the text content length in the keyboardinput element
        if (newLen > 2 * UI.defaultKeyboardinputLen) {
            UI.keyboardinputReset();
        } else if (newLen < 1) {
            // There always have to be some text in the keyboardinput
            // element with which backspace can interact.
            UI.keyboardinputReset();
            // This sometimes causes the keyboard to disappear for a second
            // but it is required for the android keyboard to recognize that
            // text has been added to the field
            event.target.blur();
            // This has to be ran outside of the input handler in order to work
            setTimeout(event.target.focus.bind(event.target), 0);
        } else {
            UI.lastKeyboardinput = newValue;
        }
    },

/* ------^-------
 *   /KEYBOARD
 * ==============
 *   EXTRA KEYS
 * ------v------*/

    sendKey(keysym, code, down) {
        UI.rfb.sendKey(keysym, code, down);

        // Move focus to the screen in order to be able to use the
        // keyboard right after these extra keys.
        // The exception is when a virtual keyboard is used, because
        // if we focus the screen the virtual keyboard would be closed.
        // In this case we focus our special virtual keyboard input
        // element instead.
        if (document.getElementById('noVNC_keyboard_button')
            .classList.contains("noVNC_selected")) {
            document.getElementById('noVNC_keyboardinput').focus();
        } else {
            UI.rfb.focus();
        }
        // fade out the controlbar to highlight that
        // the focus has been moved to the screen
        UI.idleControlbar();
    },

/* ------^-------
 *   /EXTRA KEYS
 * ==============
 *     MISC
 * ------v------*/

    updateViewOnly() {
        if (!UI.rfb) return;
        UI.rfb.viewOnly = UI.getSetting('view_only');

        // Hide input related buttons in view only mode
        if (UI.rfb.viewOnly) {
            document.getElementById('noVNC_keyboard_button')
                .classList.add('noVNC_hidden');
        } else {
            document.getElementById('noVNC_keyboard_button')
                .classList.remove('noVNC_hidden');
        }
    },

    updateLogging() {
        const level = UI.getSetting('logging');
        WebUtil.initLogging(level);
        if (UI.audioContext) {
            UI.audioContext.player.initLogging(level);
        }
        if (UI.fileManager) {
            UI.fileManager.initLogging(level);
        }
        if (UI.notificationService) {
            UI.notificationService.initLogging(level);
        }
    },

    updateDesktopName(e) {
        UI.desktopName = e.detail.name;
        // Display the desktop name in the document title
        document.title = e.detail.name;
    },

/* ------^-------
 *    /MISC
 * ==============
 *     AUDIO
 * ------v------*/

    toggleAudio() {
        if (!UI.audioContext) return;
        UI.audioContext.audioEnabled = !UI.audioContext.audioEnabled;

        if (UI.audioContext.audioEnabled) {
            // Get previous volume value.
            let volume = parseInt(WebUtil.readSetting('audio_volume', '90'));
            if (volume < 0) volume = 0;
            if (volume > 100) volume = 100;

            // Restore the volume slider to the previous value.
            document.getElementById("noVNC_setting_audio_volume").value = Math.max(15, volume).toString();
        } else {
            // Mute audio: set the volume slider to 0.
            document.getElementById("noVNC_setting_audio_volume").value = "0";
        }

        UI.updateAudio();
    },

    updateAudioVolume() {
        if (!UI.audioContext) return;

        // Get the current volume value from the slider.
        let volume = parseInt(document.getElementById("noVNC_setting_audio_volume").value);
        if (volume < 0) volume = 0;
        if (volume > 100) volume = 100;

        if (volume == 0) {
            UI.audioContext.audioEnabled = false;
        } else {
            UI.audioContext.audioEnabled = true;
        }

        UI.updateAudio();
    },

    updateAudio() {
        if (!UI.audioContext) return;

        function connectWebSocket() {
            const host = UI.getSetting('host');
            const port = UI.getSetting('port');
            const audio_path = UI.getSetting('audio_path');

            let url;
            url = UI.getSetting('encrypt') ? 'wss' : 'ws';
            url += '://' + host;
            if (port) {
                url += ':' + port;
            }
            url += '/' + window.location.pathname.substr(1) + audio_path;

            if (!UI.audioContext.audioEnabled) return;

            Log.Info("Establishing WebSocket connection for audio...");
            UI.audioContext.webSocket = new WebSocket(url, ['binary']);
            UI.audioContext.webSocket.binaryType = 'arraybuffer';

            UI.audioContext.webSocket.onmessage = (event) => {
                UI.audioContext.player.feed(event.data);
            };

            UI.audioContext.webSocket.onopen = function(e) {
                Log.Info("WebSocket connection for audio established");
            };

            UI.audioContext.webSocket.onclose = function(event) {
                if (event.wasClean) {
                    Log.Info(`WebSocket connection for audio closed, code=${event.code} reason=${event.reason}`);
                } else {
                    // e.g. server process killed or network down
                    // event.code is usually 1006 in this case
                    Log.Info('WebSocket connection for audio died');
                }

                // Destroy the connection.
                delete UI.audioContext.webSocket
                UI.audioContext.webSocket = null

                // Attempt to re-connect.
                if (UI.audioContext.audioEnabled) {
                    Log.Info('WebSocket reconnection for audio will be attempted');
                    setTimeout(connectWebSocket, 1000);
                }
            };
        }

        const audioButtonIcon = document.getElementById("noVNC_audio_button_icon");
        const audioVolumeSlider = document.getElementById("noVNC_setting_audio_volume");

        if (UI.audioContext.audioEnabled && UI.connected) {
            // Audio should be enabled.

            // Get the current volume value.
            let volume = parseInt(document.getElementById("noVNC_setting_audio_volume").value);
            if (volume <= 0) volume = 1;  // We should not be muted.
            if (volume > 100) volume = 100;

            // Set the volume value.
            UI.audioContext.player.volume(volume / 100);

            // Make sure the PCM player is started.
            UI.audioContext.player.start();

            // Make sure the WebSocket connection is established.
            if (!UI.audioContext.webSocket) {
                connectWebSocket();
            }

            // Update the interface.
            audioButtonIcon.classList.remove("fa-volume-mute");
            audioButtonIcon.classList.add("fa-volume-up");
        }
        else {
            // Audio should be disabled.

            // Close the WebSocket connection.
            if (UI.audioContext.webSocket) {
                UI.audioContext.webSocket.close();
                // The WebSocket close callback will destroy the object.
            }

            // Stop the PCM player.
            UI.audioContext.player.stop();

            // Update the interface.
            audioButtonIcon.classList.remove("fa-volume-up");
            audioButtonIcon.classList.add("fa-volume-mute");
        }
    },

/* ------^-------
 *    /AUDIO
 * ==============
 *  FILE MANAGER
 * ------v------*/

    closeFileManager() {
        if (UI.fileManager) {
            const fileManagerBtn = document.getElementById('noVNC_file_manager_button');
            fileManagerBtn.classList.remove('noVNC_selected');
            UI.fileManager.close();
        }
    },

    toggleFileManager() {
        if (UI.fileManager) {
            const fileManagerBtn = document.getElementById('noVNC_file_manager_button');
            if (fileManagerBtn.classList.contains('noVNC_selected')) {
                fileManagerBtn.classList.remove('noVNC_selected');
                UI.fileManager.close();
            } else {
                fileManagerBtn.classList.add('noVNC_selected');
                UI.fileManager.open();
                UI.closeControlbar();
            }
        }
    },

/* ------^-------
 * /FILE MANAGER
 * ==============
 */

};

export default UI;
