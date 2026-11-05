import * as Log from '../core/util/logging.js';

const MIME_TYPES = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus'];
const MAX_BUFFERED_BYTES = 32 * 1024;
const SETUP_TIMEOUT_MS = 10000;
const CAPTURE_TIMEOUT_MS = 30000;
const CLOSE_TIMEOUT_MS = 1500;
const RECORDER_STOP_TIMEOUT_MS = 1000;

function withTimeout(promise, duration, operation) {
    let timer;
    return Promise.race([
        promise,
        new Promise((_, reject) => {
            timer = setTimeout(() => {
                const error = new Error(`${operation} timed out`);
                error.name = 'TimeoutError';
                reject(error);
            }, duration);
        }),
    ]).finally(() => clearTimeout(timer));
}

function stopTracks(stream) {
    stream?.getTracks().forEach(track => track.stop());
}

function microphoneUnavailableReason(media, mimeType) {
    if (!window.isSecureContext) {
        return 'Microphone access requires HTTPS (or localhost).';
    }
    const policy = document.permissionsPolicy || document.featurePolicy;
    if (policy?.allowsFeature?.('microphone') === false) {
        return 'Microphone access is blocked for this page. Open the desktop directly in a browser tab, or allow microphone access for the embedded page.';
    }
    if (!media?.getUserMedia || !mimeType) {
        return 'This browser cannot record Opus microphone audio. Try a browser supporting WebM/Opus or Ogg/Opus.';
    }
    return '';
}

function supportedMimeType() {
    if (!window.MediaRecorder?.isTypeSupported) return null;
    return MIME_TYPES.find(type => MediaRecorder.isTypeSupported(type)) || null;
}

function captureConstraints(deviceId) {
    const audio = {
        channelCount: { ideal: 1 },
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
    };
    if (deviceId) audio.deviceId = { exact: deviceId };
    return { audio };
}

export default class Microphone {
    constructor(controls, url, reportError) {
        for (const key of ['button', 'select', 'label', 'icon', 'status']) {
            if (!controls[key]) throw new TypeError(`Missing microphone control: ${key}`);
            this[key] = controls[key];
        }

        this.url = url;
        this.reportError = reportError;
        // Session identity invalidates callbacks from cancelled permissions and recordings.
        this.session = null;
        this.connected = false;
        this.devices = [];
        this.selectedId = '';
        this.devicesRequest = 0;
        this.scanning = false;
        // Device switches wait for every previous recording/socket to finish closing.
        this.transportClosed = Promise.resolve();
        this.media = navigator.mediaDevices;
        this.mimeType = supportedMimeType();
        this.unavailable = microphoneUnavailableReason(this.media, this.mimeType);

        this.bindEvents();
        this.render();
        this.setStatus(this.unavailable || 'Connect to the desktop to use your microphone.');
    }

    bindEvents() {
        this.button.addEventListener('click', () => {
            if (this.session) this.stop();
            else void this.start();
        });
        this.select.addEventListener('change', () => {
            this.selectedId = this.select.value;
            if (this.session) void this.switchMicrophone();
            else this.setStatus('Microphone off. Enable to use the selected microphone.');
        });

        const refreshOnOpen = () => this.refreshDevicesOnOpen();
        this.select.addEventListener('focus', refreshOnOpen);
        this.select.addEventListener('pointerdown', refreshOnOpen);
        this.select.addEventListener('keydown', event => {
            if (['ArrowDown', 'ArrowUp', ' ', 'Enter'].includes(event.key)) refreshOnOpen();
        });
        this.media?.addEventListener?.('devicechange', () => {
            void this.refreshDevices({ deviceChange: true });
        });
        window.addEventListener('pagehide', () => this.stop('Microphone off', { graceful: false }));
    }

    refreshDevicesOnOpen() {
        if (this.select.disabled || this.scanning) return;
        void this.refreshDevices({ manual: true });
    }

    setStatus(message, { error = false, severity = error ? 'error' : 'info' } = {}) {
        this.statusError = error;
        this.status.textContent = error ? message : '';
        this.status.classList.toggle('noVNC_hidden', !error);
        if (severity === 'error') Log.Error(message);
        else if (severity === 'warn') Log.Warn(message);
        else Log.Info(message);
    }

    render() {
        const active = Boolean(this.session?.sending);
        const pending = Boolean(this.session && !active);
        const disabled = !this.connected || Boolean(this.unavailable);

        this.button.disabled = disabled;
        this.label.textContent = active ? 'Disable microphone'
            : pending ? 'Cancel microphone' : 'Enable microphone';
        this.button.setAttribute('aria-pressed', String(active));
        this.button.title = active
            ? 'Stop sending your microphone to the container'
            : pending ? 'Cancel microphone access'
                : 'Send the selected microphone to the container';
        this.icon.classList.toggle('fa-microphone', active);
        this.icon.classList.toggle('fa-microphone-slash', !active);

        // Changing devices starts a new recording and requires a new socket.
        this.select.disabled = disabled || pending;
        this.renderDevices();
    }

    setConnected(connected) {
        this.connected = connected;
        if (!connected) this.stop('Connect to the desktop to use your microphone.');
        else if (!this.unavailable) void this.refreshDevices();
        if (this.unavailable) this.setStatus(this.unavailable, { error: true });
        this.render();
    }

    deviceOptions() {
        const defaultName = (!this.selectedId && this.session?.deviceLabel) || this.defaultLabel;
        const options = [
            ['', defaultName ? `Default (${defaultName})` : 'Default'],
            ...this.devices.map((device, index) => [
                device.deviceId, device.label || `Microphone ${index + 1}`,
            ]),
        ];
        if (this.selectedId && !options.some(([id]) => id === this.selectedId)) {
            options.push([this.selectedId, this.session?.deviceLabel || 'Selected microphone']);
        }
        return options;
    }

    renderDevices() {
        const options = this.deviceOptions();
        const signature = JSON.stringify(options);
        // Preserve the open native selector if its options have not changed.
        if (this.renderedDevices !== signature) {
            this.renderedDevices = signature;
            this.select.replaceChildren();
            for (const [value, label] of options) {
                const option = document.createElement('option');
                option.value = value;
                option.textContent = label;
                option.title = label;
                this.select.appendChild(option);
            }
        }
        if (this.select.value !== this.selectedId) this.select.value = this.selectedId;
        this.select.title = this.select.selectedOptions[0]?.textContent || 'Microphone source';
    }

    updateDeviceList(allDevices) {
        const inputs = allDevices.filter(device =>
            device.kind === 'audioinput' && device.deviceId);

        // Chromium exposes "default" and "communications" as aliases.
        const physical = inputs.filter(device =>
            !['default', 'communications'].includes(device.deviceId));
        const defaultAlias = inputs.find(device => device.deviceId === 'default');
        const defaultDevice = physical.find(device =>
            defaultAlias?.groupId && device.groupId === defaultAlias.groupId)
            || defaultAlias || physical[0];

        this.defaultLabel = defaultDevice?.label?.replace(/^default\s*[-:]\s*/i, '')
            || this.defaultLabel;
        this.devices = physical.filter((device, index) =>
            physical.findIndex(other => other.deviceId === device.deviceId) === index);

        return Boolean(this.selectedId &&
            !this.devices.some(device => device.deviceId === this.selectedId));
    }

    handleMissingDevice(missing, deviceChange) {
        if (deviceChange && missing && this.session?.stream) {
            this.fail(this.session, 'The selected microphone was disconnected or access was revoked. Reconnect a microphone and enable it again.');
        } else if (deviceChange && missing && !this.session) {
            this.setStatus('The selected microphone is no longer available. Connect a microphone and enable it again.', { severity: 'warn' });
        }
        if (missing && !this.session) this.selectedId = '';
    }

    reportDeviceRefresh(manual, deviceChange, missing) {
        if (!this.session && this.connected && !(deviceChange && missing) && (manual || !this.statusError)) {
            this.setStatus(!this.devices.length
                ? 'No microphones are listed. Connect a microphone and enable access.'
                : 'Microphone off. Enable it to select a source.');
        }
        if (manual && this.session) this.setStatus('Microphone list refreshed.');
    }

    async refreshDevices({ manual = false, deviceChange = false } = {}) {
        if (this.unavailable) return;
        if (!this.media.enumerateDevices) {
            if (!this.session && !this.statusError) {
                this.setStatus('Your browser cannot list microphones. Enable to use the default microphone.');
            }
            return;
        }
        const request = ++this.devicesRequest;
        this.scanning = true;
        this.render();
        try {
            const devices = await this.media.enumerateDevices();
            if (request !== this.devicesRequest) return;
            const missing = this.updateDeviceList(devices);
            this.handleMissingDevice(missing, deviceChange);
            this.renderDevices();
            this.reportDeviceRefresh(manual, deviceChange, missing);
        } catch (error) {
            if (request === this.devicesRequest && this.connected) {
                Log.Warn(`Microphone device enumeration failed: ${error}`);
                if (manual) {
                    this.setStatus('Could not update the microphone list. Try reopening the source selector.', { error: true, severity: 'warn' });
                }
            }
        } finally {
            if (request === this.devicesRequest) {
                this.scanning = false;
                this.render();
            }
        }
    }

    static captureError(error) {
        switch (error?.name) {
            case 'NotFoundError':
            case 'DevicesNotFoundError':
                return 'No microphone was recognized. Connect a microphone and try again.';
            case 'NotAllowedError':
            case 'PermissionDeniedError':
                return 'Microphone access was blocked. Allow microphone access in your browser\'s site settings, then enable it again.';
            case 'OverconstrainedError':
            case 'ConstraintNotSatisfiedError':
                return 'The selected microphone is no longer available. Connect an available microphone and enable it again.';
            case 'NotReadableError':
            case 'TrackStartError':
            case 'AbortError':
                return 'The microphone could not be opened. Check that it is connected and not being used by another application, then try again.';
            case 'TimeoutError':
                return 'Microphone access timed out. Respond to the browser permission prompt and retry.';
            case 'NotSupportedError':
                return 'This browser could not start Opus microphone recording. Try a browser supporting WebM/Opus or Ogg/Opus.';
            case 'SecurityError':
                return 'Microphone access is disabled by your browser or its security settings. Allow access for this site and try again.';
            default:
                return 'Could not start the microphone. Check that a microphone is connected and allowed in your browser, then try again.';
        }
    }

    isCurrentSession(session) {
        return this.session === session;
    }

    releaseInput(session) {
        if (session.stream) {
            stopTracks(session.stream);
            session.stream = null;
        }
    }

    watchTrack(session, track) {
        track.addEventListener('ended', () => {
            if (this.isCurrentSession(session)) {
                this.fail(session, 'Microphone access ended or the device was disconnected. Reconnect a microphone and enable it again.');
            }
        });
        track.addEventListener('mute', () => {
            if (this.isCurrentSession(session)) {
                this.setStatus('The microphone is temporarily muted or unavailable. Check the device and browser settings.', { severity: 'warn' });
            }
        });
        track.addEventListener('unmute', () => {
            if (this.isCurrentSession(session) && session.sending) this.showSending(session);
        });
    }

    async acquire(session, deviceId) {
        const stream = await this.media.getUserMedia(captureConstraints(deviceId));
        if (!this.isCurrentSession(session)) {
            stopTracks(stream);
            return null;
        }
        session.stream = stream;
        const track = stream.getAudioTracks()[0];
        if (!track || track.readyState === 'ended') throw new DOMException('', 'NotFoundError');
        session.deviceLabel = track.label || 'Selected microphone';
        // Selecting "Default" must not pin the resolved physical device.
        if (!deviceId) this.defaultLabel = track.label || this.defaultLabel;
        this.watchTrack(session, track);
        // Permission makes labels available; enumeration does not prompt for capture.
        void this.refreshDevices();
        return stream;
    }

    showSending(session) {
        const muted = session.stream?.getAudioTracks()[0]?.muted;
        this.setStatus(muted
            ? 'The microphone is temporarily muted or unavailable. Check the device and browser settings.'
            : `Sending: ${session.deviceLabel}`, { severity: muted ? 'warn' : 'info' });
    }

    createRecorder(session, stream) {
        const recorder = new MediaRecorder(stream, {
            mimeType: this.mimeType,
            audioBitsPerSecond: 64000,
        });

        recorder.ondataavailable = ({ data }) => {
            if (data.size) this.send(session, data);
        };
        recorder.onerror = event => this.fail(session,
            'Microphone encoding stopped. Enable the microphone again to retry.', event.error);
        recorder.onstop = () => this.fail(session,
            'Microphone recording ended. Enable it again to retry.');
        return recorder;
    }

    startRecording(session) {
        if (!this.isCurrentSession(session)) return;
        clearTimeout(session.connectionTimer);
        try {
            session.recorder.start(100);
            session.sending = true;
            this.render();
            this.showSending(session);
        } catch (error) {
            this.fail(session, 'Microphone encoding could not start. Enable it again to retry.', error);
        }
    }

    connect(session) {
        const socket = new WebSocket(this.url(), ['binary']);
        session.socket = socket;
        socket.onopen = () => this.startRecording(session);
        socket.onclose = event => this.fail(session,
            session.sending
                ? 'The microphone stream disconnected. Enable it again to reconnect.'
                : 'Could not open the microphone stream. Another desktop session may be using it. Try again.',
            `close code=${event.code}, clean=${event.wasClean}`);
        socket.onerror = () => this.fail(session,
            'Could not connect the microphone stream. Check your connection and sign in again if needed.');

        session.connectionTimer = setTimeout(() => this.fail(session,
            'The microphone connection timed out. Check your connection and try again.'),
            SETUP_TIMEOUT_MS);
        this.setStatus('Connecting the selected microphone…');
    }

    async prepareSession(session) {
        const stream = await withTimeout(
            this.acquire(session, this.selectedId),
            CAPTURE_TIMEOUT_MS,
            'Microphone permission/device acquisition'
        );
        if (!stream || !this.isCurrentSession(session)) return;

        // A fresh recording must not send its container header to the old decoder.
        await this.transportClosed;
        if (!this.isCurrentSession(session)) return;

        session.recorder = this.createRecorder(session, stream);
        this.connect(session);
    }

    async start() {
        if (this.session || !this.connected || this.unavailable) return;

        const session = { sending: false, chunks: 0, bytes: 0 };
        this.session = session;
        this.render();
        this.setStatus('Waiting for microphone permission. Allow the selected microphone, or cancel.');

        try {
            await this.prepareSession(session);
        } catch (error) {
            this.fail(session, Microphone.captureError(error), error);
        }
    }

    send(session, data) {
        if ((!this.isCurrentSession(session) && !session.finishing) || session.socket?.readyState !== WebSocket.OPEN) return;
        if (session.socket.bufferedAmount + data.size > MAX_BUFFERED_BYTES) {
            // Never drop encoded chunks: subsequent chunks depend on this container.
            this.fail(session, 'The microphone connection is too slow. Check your network and enable it again.');
            return;
        }
        try {
            session.socket.send(data); // Blob ordering is handled by the browser.
            session.chunks++;
            session.bytes += data.size;
        } catch (error) {
            this.fail(session, 'The microphone stream could not send audio. Enable it again to retry.', error);
        }
    }

    switchMicrophone() {
        if (!this.session) return;
        // A new recorder must send fresh WebM/Ogg headers to a new decoder.
        this.stop('Switching microphones…');
        return this.start();
    }

    fail(session, message, cause = null) {
        if (!this.isCurrentSession(session)) return;
        Log.Error(`Microphone failure: ${message}${cause ? `; cause=${cause}` : ''}`);
        this.stop(message, { error: true });
        try {
            this.reportError?.(message);
        } catch (error) {
            Log.Error(`Microphone error reporter failed: ${error}`);
        }
        void this.refreshDevices();
    }

    closeTransport(socket) {
        if (socket.readyState === WebSocket.CLOSED) return Promise.resolve();

        return new Promise(resolve => {
            const finish = () => {
                clearTimeout(timer);
                socket.removeEventListener('close', finish);
                resolve();
            };
            const timer = setTimeout(finish, CLOSE_TIMEOUT_MS);
            socket.addEventListener('close', finish, { once: true });

            try {
                socket.close();
            } catch (error) {
                Log.Warn(`Microphone close failed: ${error}`);
                finish();
            }
        });
    }

    finishRecording(session, graceful) {
        const recorder = session.recorder;
        if (!recorder || recorder.state === 'inactive') return Promise.resolve();

        // During a graceful stop, allow the final encoded Blob to be sent.
        session.finishing = graceful;
        if (!graceful) recorder.ondataavailable = null;
        recorder.onerror = null;
        recorder.onstop = null;

        return new Promise(resolve => {
            const finish = () => {
                clearTimeout(timer);
                recorder.removeEventListener('stop', finish);
                resolve();
            };
            const timer = setTimeout(finish, RECORDER_STOP_TIMEOUT_MS);
            recorder.addEventListener('stop', finish, { once: true });

            try {
                recorder.stop();
            } catch (error) {
                Log.Warn(`Microphone recorder stop failed: ${error}`);
                finish();
            }
        });
    }

    async closeSession(session, graceful) {
        clearTimeout(session.connectionTimer);
        if (session.socket) {
            // Cleanup owns the socket now; ignore its normal event handlers.
            session.socket.onopen = null;
            session.socket.onclose = null;
            session.socket.onerror = null;
        }
        const finished = this.finishRecording(session, graceful);
        this.releaseInput(session); // Release the physical microphone before waiting.
        await finished;

        session.finishing = false;
        if (session.recorder) session.recorder.ondataavailable = null;
        Log.Info(`Microphone stopped: chunks=${session.chunks}, bytes=${session.bytes}`);
        if (session.socket) await this.closeTransport(session.socket);
    }

    stop(message = 'Microphone off', { error = false, graceful = true } = {}) {
        const session = this.session;
        this.session = null; // Pending permissions and callbacks become obsolete immediately.
        if (session) {
            const closing = this.closeSession(session, graceful && !error);
            // Preserve earlier cleanup even if this session was cancelled before connecting.
            this.transportClosed = Promise.all([this.transportClosed, closing]).then(() => { });
        }
        this.render();
        this.setStatus(message, { error });
        return this.transportClosed;
    }
}
