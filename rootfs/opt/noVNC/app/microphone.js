import * as Log from '../core/util/logging.js';

const MIME_TYPE = 'audio/webm;codecs=opus';
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
    const policy = document.permissionsPolicy || document.featurePolicy;
    if (policy?.allowsFeature?.('microphone') === false) {
        return 'Microphone access is blocked for this page.';
    }
    if (!media?.getUserMedia || !mimeType) {
        return 'This browser cannot record Opus microphone audio.';
    }
    return '';
}

function supportedMimeType() {
    if (!window.MediaRecorder?.isTypeSupported) return null;
    return MediaRecorder.isTypeSupported(MIME_TYPE) ? MIME_TYPE : null;
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
    constructor(controls, url) {
        for (const key of ['button', 'select', 'icon']) {
            if (!controls[key]) throw new TypeError(`Missing microphone control: ${key}`);
            this[key] = controls[key];
        }

        this.url = url;
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
        if (this.unavailable) Log.Error(this.unavailable);
    }

    bindEvents() {
        this.button.addEventListener('click', () => {
            if (this.session) this.stop();
            else void this.start();
        });
        this.select.addEventListener('change', () => {
            this.selectedId = this.select.value;
            if (this.session) void this.switchMicrophone();
        });
        this.select.addEventListener('pointerdown', () => {
            if (this.select.disabled || this.scanning) return;
            void this.refreshDevices();
        });
        this.media?.addEventListener?.('devicechange', () => {
            void this.refreshDevices({ deviceChange: true });
        });
        window.addEventListener('pagehide', () => this.stop({ graceful: false }));
    }

    render() {
        const active = Boolean(this.session?.sending);
        const pending = Boolean(this.session && !active);
        const disabled = !this.connected || Boolean(this.unavailable);

        this.button.disabled = disabled;
        this.button.setAttribute('aria-pressed', String(active));
        this.button.title = active
            ? 'Disable microphone'
            : pending ? 'Cancel microphone'
                : 'Enable microphone';
        this.icon.classList.toggle('fa-microphone', active);
        this.icon.classList.toggle('fa-microphone-slash', !active);

        // Changing devices starts a new recording and requires a new socket.
        this.select.disabled = disabled || pending;
        this.renderDevices();
    }

    setConnected(connected) {
        this.connected = connected;
        if (!connected) this.stop();
        else if (!this.unavailable) void this.refreshDevices();
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

        // An empty label means the browser has withdrawn permission and is no
        // longer naming devices. Drop the name remembered from the last capture.
        const revealed = inputs.some(device => device.label);
        this.defaultLabel = revealed
            ? (defaultDevice?.label?.replace(/^default\s*[-:]\s*/i, '') || this.defaultLabel)
            : '';
        this.devices = physical.filter((device, index) =>
            physical.findIndex(other => other.deviceId === device.deviceId) === index);

        return Boolean(this.selectedId &&
            !this.devices.some(device => device.deviceId === this.selectedId));
    }

    handleMissingDevice(missing, deviceChange) {
        if (deviceChange && missing && this.session?.stream) {
            this.fail(this.session, 'The selected microphone was disconnected or access was revoked.');
        } else if (deviceChange && missing && !this.session) {
            Log.Warn('The selected microphone is no longer available.');
        }
        if (missing && !this.session) this.selectedId = '';
    }

    async refreshDevices({ deviceChange = false } = {}) {
        if (this.unavailable) return;
        if (!this.media.enumerateDevices) {
            if (!this.noDeviceList) {
                this.noDeviceList = true;
                Log.Warn('This browser cannot list microphones.');
            }
            return;
        }
        const request = ++this.devicesRequest;
        this.scanning = true;
        try {
            const devices = await this.media.enumerateDevices();
            if (request !== this.devicesRequest) return;
            const missing = this.updateDeviceList(devices);
            this.handleMissingDevice(missing, deviceChange);
        } catch (error) {
            if (request === this.devicesRequest && this.connected) {
                Log.Warn(`Microphone device enumeration failed: ${error}`);
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
                return 'No microphone was recognized.';
            case 'NotAllowedError':
                return 'Microphone access was blocked.';
            case 'OverconstrainedError':
                return 'The selected microphone is no longer available.';
            case 'NotReadableError':
            case 'AbortError':
                return 'The microphone could not be opened.';
            case 'TimeoutError':
                return 'Microphone access timed out.';
            case 'NotSupportedError':
                return 'This browser could not start Opus microphone recording.';
            case 'SecurityError':
                return 'Microphone access is disabled.';
            default:
                return 'Could not start the microphone.';
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
                this.fail(session, 'Microphone access ended or the device was disconnected.');
            }
        });
        track.addEventListener('mute', () => {
            if (this.isCurrentSession(session)) {
                Log.Warn('The microphone is temporarily muted or unavailable.');
            }
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

    createRecorder(session, stream) {
        const recorder = new MediaRecorder(stream, {
            mimeType: this.mimeType,
            audioBitsPerSecond: 64000,
        });
        recorder.ondataavailable = ({ data }) => {
            if (!data.size) return;
            this.send(session, data);
        };
        recorder.onerror = event => this.fail(session,
            'Microphone encoding stopped.', event.error);
        recorder.onstop = () => this.fail(session,
            'Microphone recording ended.');
        return recorder;
    }

    startRecording(session) {
        if (!this.isCurrentSession(session)) return;
        clearTimeout(session.connectionTimer);
        try {
            // 100 ms matches the original client. The bridge writes each
            // decoded blob as it arrives.
            session.recorder.start(100);
            session.sending = true;
            this.render();
        } catch (error) {
            this.fail(session, 'Microphone encoding could not start.', error);
        }
    }

    connect(session) {
        const socket = new WebSocket(this.url(), ['binary']);
        session.socket = socket;
        socket.onopen = () => this.startRecording(session);
        socket.onclose = event => this.fail(session,
            session.sending
                ? 'The microphone stream disconnected.'
                : 'Could not open the microphone stream.',
            `close code=${event.code}, clean=${event.wasClean}`);
        socket.onerror = () => this.fail(session,
            'Could not connect the microphone stream.');

        session.connectionTimer = setTimeout(() => this.fail(session,
            'The microphone connection timed out.'),
            SETUP_TIMEOUT_MS);
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

        const session = { sending: false };
        this.session = session;
        this.render();

        try {
            await this.prepareSession(session);
        } catch (error) {
            this.fail(session, Microphone.captureError(error), error);
        }
    }

    send(session, data) {
        if ((!this.isCurrentSession(session) && !session.finishing) || session.socket?.readyState !== WebSocket.OPEN) return;
        const size = data.size;
        if (session.socket.bufferedAmount + size > MAX_BUFFERED_BYTES) {
            this.fail(session, 'The microphone connection is too slow.');
            return;
        }
        try {
            session.socket.send(data);
        } catch (error) {
            this.fail(session, 'The microphone stream could not send audio.', error);
        }
    }

    switchMicrophone() {
        if (!this.session) return;
        // A new recorder sends a new container header to a new decoder.
        this.stop();
        return this.start();
    }

    fail(session, message, cause = null) {
        if (!this.isCurrentSession(session)) return;
        Log.Error(`Microphone failure: ${message}${cause ? `; cause=${cause}` : ''}`);
        this.stop({ error: true });
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

        // The final blob is produced by stop(). Closing the socket first drops it.
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
        this.releaseInput(session);
        await finished;
        if (session.recorder) session.recorder.ondataavailable = null;
        session.finishing = false;
        if (session.socket) await this.closeTransport(session.socket);
    }

    stop({ error = false, graceful = true } = {}) {
        const session = this.session;
        this.session = null; // Pending permissions and callbacks become obsolete immediately.
        if (session) {
            const closing = this.closeSession(session, graceful && !error);
            // Preserve earlier cleanup even if this session was cancelled before connecting.
            this.transportClosed = Promise.all([this.transportClosed, closing]).then(() => { });
        }
        this.render();
        return this.transportClosed;
    }
}
