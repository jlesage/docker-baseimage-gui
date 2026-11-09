import { unmute } from "./unmute.min.js"
import * as Log from '../core/util/logging.js';

export function PCMPlayer(option) {
    this.init(option);
}

const PCMEncodingDefinitions = {
    '8bitInt': {
        bitDepth: 8,
        sampleSize: 8 / 8,
        maxValue: 128,
        peekFunction: function(data, offset) { return DataView.prototype.getInt8.call(data, offset); },
    },
    '16bitIntLE': {
        bitDepth: 16,
        sampleSize: 16 / 8,
        maxValue: 32768,
        peekFunction: function(data, offset) { return DataView.prototype.getInt16.call(data, offset, true /* littleEndian */); },
    },
    '16bitIntBE': {
        bitDepth: 16,
        sampleSize: 16 / 8,
        maxValue: 32768,
        peekFunction: function(data, offset) { return DataView.prototype.getInt16.call(data, offset, false /* bigEndian */); },
    },
    '32bitIntLE': {
        bitDepth: 32,
        sampleSize: 32 / 8,
        maxValue: 2147483648,
        peekFunction: function(data, offset) { return DataView.prototype.getInt32.call(data, offset, true /* littleEndian */); },
    },
    '32bitIntBE': {
        bitDepth: 32,
        sampleSize: 32 / 8,
        maxValue: 2147483648,
        peekFunction: function(data, offset) { return DataView.prototype.getInt32.call(data, offset, false /* bigEndian */); },
    },
    '32bitFloatLE': {
        bitDepth: 32,
        sampleSize: 32 / 8,
        maxValue: 1,
        peekFunction: function(data, offset) { return DataView.prototype.getFloat32.call(data, offset, true /* littleEndian */); },
    },
    '32bitFloatBE': {
        bitDepth: 32,
        sampleSize: 32 / 8,
        maxValue: 1,
        peekFunction: function(data, offset) { return DataView.prototype.getFloat32.call(data, offset, false /* bigEndian */); },
    },
}

const EMPTY_RX = new Uint8Array(0);

PCMPlayer.prototype.init = function(option) {
    var defaults = {
        encoding: '16bitIntLE',
        channels: 2,
        sampleRate: 48000,
        bufferAudioTime: 20, /* in milliseconds */
        maxAudioLag: 250, /* in milliseconds */
        reduceClickingNoise: false,
    };
    this.option = Object.assign({}, defaults, option);
    this.option.maxAudioLag = Math.max(this.option.maxAudioLag, this.option.bufferAudioTime * 2);

    // Select the encoding definitions to use.
    this.encodingDefs = PCMEncodingDefinitions[this.option.encoding] ?
        PCMEncodingDefinitions[this.option.encoding] : PCMEncodingDefinitions['16bitIntLE'];

    // Initialize state of the player.
    this.started = false;
    this.gainValue = 1;

    // Initialize samples array.
    const samplesBufferLength = Math.floor(this.option.bufferAudioTime * this.option.sampleRate / 1000) * this.option.channels;
    this.samplesBuffer = new Float32Array(samplesBufferLength);
    this.samplesCount = 0;

    this.rx = EMPTY_RX;
    this.rxOffset = 0;
    this.headerParsed = false;
    this.streamBroken = false;

    // Audio context is created in start(), when the user enables audio.
};

PCMPlayer.prototype.initLogging = function(level) {
    Log.initLogging(level)
}

PCMPlayer.prototype.createAudioContext = function(sampleRate) {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    try {
        this.audioCtx = new Ctx({ sampleRate: sampleRate });
    } catch (err) {
        Log.Info("AudioContext refused sampleRate " + sampleRate + ": " + err);
        this.audioCtx = new Ctx();
    }
    if (this.audioCtx.sampleRate !== sampleRate) {
        Log.Info("AudioContext sampleRate is " + this.audioCtx.sampleRate + " (requested " + sampleRate + ")");
    }

    // Enables web audio playback with the ios mute switch on.
    // https://github.com/swevans/unmute
    this.unmuteHandle = unmute(this.audioCtx);

    // Context needs to be resumed on iOS and Safari (or it will stay in "suspended" state).
    this.audioCtx.resume();

    // Handle audio context state changes.
    this.audioCtx.onstatechange = () => {
        if (!this.audioCtx) return;

        Log.Info("AudioContext state: " + this.audioCtx.state);

        // If the state is not running, clear any pending samples we have.
        if (this.audioCtx.state != 'running') {
            this.startTime = 0;
            this.samplesCount = 0;
        }
    };

    this.gainNode = this.audioCtx.createGain();
    this.gainNode.gain.value = this.gainValue;
    this.gainNode.connect(this.audioCtx.destination);
};

PCMPlayer.prototype.destroyAudioContext = function() {
    if (this.unmuteHandle) {
        this.unmuteHandle.dispose();
        this.unmuteHandle = null;
    }
    if (this.audioCtx) {
        this.audioCtx.close();
        this.audioCtx = null;
    }
}

PCMPlayer.prototype.start = function() {
    if (this.started) return;
    this.startTime = 0;
    this.samplesCount = 0;
    this.started = true;
    // Resume before the socket opens so the first framed records are not
    // dropped while the context is still suspended.
    if (!this.audioCtx) {
        this.createAudioContext(this.option.sampleRate);
    }
}

// A new socket starts a new byte stream. Call this from the WebSocket onopen
// handler, before the first message is parsed.
PCMPlayer.prototype.resetStream = function() {
    this.rx = EMPTY_RX;
    this.rxOffset = 0;
    this.headerParsed = false;
    this.streamBroken = false;
    this.samplesCount = 0;
    this.startTime = 0;
}

PCMPlayer.prototype.stop = function() {
    if (!this.started) return;
    this.started = false;
}

PCMPlayer.prototype.volume = function(volume) {
    if (!this.started) return;
    if (volume < 0 || volume > 1) return;
    this.gainValue = volume;
    this.gainNode.gain.value = volume;
};

PCMPlayer.prototype.destroy = function() {
    this.stop();
    this.destroyAudioContext();
};

const STREAM_HEADER_BYTES = 12;
const RECORD_HEADER_BYTES = 5;
const MAX_RECORD_BYTES = 1024 * 1024;

// A whole message is viewed in place. Bytes are copied only when a record
// was split and the previous message left a tail.
PCMPlayer.prototype.appendRx = function(data) {
    const chunk = new Uint8Array(data);
    const pending = this.rx.length - this.rxOffset;
    if (pending === 0) {
        this.rx = chunk;
        this.rxOffset = 0;
        return;
    }

    const merged = new Uint8Array(pending + chunk.length);
    merged.set(this.rx.subarray(this.rxOffset), 0);
    merged.set(chunk, pending);
    this.rx = merged;
    this.rxOffset = 0;
}

PCMPlayer.prototype.applyStreamFormat = function(sampleRate, channels) {
    const samplesBufferLength = Math.floor(this.option.bufferAudioTime * sampleRate / 1000) * channels;
    const sameRate = this.audioCtx && this.option.sampleRate === sampleRate;
    const sameBuffer = sameRate &&
        this.option.channels === channels &&
        this.samplesBuffer.length === samplesBufferLength;

    this.option.sampleRate = sampleRate;
    this.option.channels = channels;

    // Keep the context and the sample buffer when the header matches.
    if (!sameBuffer) {
        this.samplesBuffer = new Float32Array(samplesBufferLength);
        this.samplesCount = 0;
    }
    if (!sameRate) {
        if (this.audioCtx) {
            this.destroyAudioContext();
        }
        this.createAudioContext(sampleRate);
    }

    Log.Info("Audio stream " + sampleRate + " Hz, " + channels + " channels");
}

PCMPlayer.prototype.pushPcm = function(bytes) {
    if (!this.audioCtx || this.audioCtx.state != 'running') return;
    if (!this.samplesBuffer.length) return;

    const frameBytes = this.encodingDefs.sampleSize * this.option.channels;
    if (frameBytes == 0 || bytes.byteLength % frameBytes != 0) {
        Log.Info("Audio PCM record is not frame aligned");
        return;
    }

    // Create a view for data to work on.
    const dataView = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

    // Get the number of samples in data.
    const numSamples = bytes.byteLength / this.encodingDefs.sampleSize;

    // Convert samples to 32bits float format.
    for (var i = 0; i < numSamples; i++) {
        this.samplesBuffer[this.samplesCount] = this.encodingDefs.peekFunction(dataView, i * this.encodingDefs.sampleSize) / this.encodingDefs.maxValue;
        this.samplesCount++;

        // Flush if needed.
        if (this.samplesCount == this.samplesBuffer.length) {
            this.flush();
            this.samplesCount = 0;
        }
    }
}

// A gap is silence that was not sent. Advance the playback clock instead of
// inserting zeros. Gaps before the first audible buffer are ignored.
PCMPlayer.prototype.applyGap = function(frames) {
    if (!this.audioCtx || this.audioCtx.state != 'running') return;

    if (this.samplesCount > 0) {
        this.flush();
        this.samplesCount = 0;
    }

    if (this.startTime == 0) return;
    this.startTime += frames / this.option.sampleRate;
}

PCMPlayer.prototype.parseRx = function() {
    if (this.streamBroken) return;

    while (true) {
        const available = this.rx.length - this.rxOffset;

        if (!this.headerParsed) {
            if (available < STREAM_HEADER_BYTES) return;

            const view = new DataView(this.rx.buffer, this.rx.byteOffset + this.rxOffset, STREAM_HEADER_BYTES);
            const magicOk = this.rx[this.rxOffset] == 0x50 &&
                this.rx[this.rxOffset + 1] == 0x43 &&
                this.rx[this.rxOffset + 2] == 0x4d &&
                this.rx[this.rxOffset + 3] == 0x31;
            const sampleRate = view.getUint32(4, true);
            const channels = view.getUint8(8);
            const format = view.getUint8(9);

            if (!magicOk || format != 1 || channels < 1 || channels > 8 || sampleRate < 8000 || sampleRate > 192000) {
                Log.Info("Unsupported audio stream header");
                this.streamBroken = true;
                return;
            }

            this.rxOffset += STREAM_HEADER_BYTES;
            this.headerParsed = true;
            this.applyStreamFormat(sampleRate, channels);
            continue;
        }

        if (available < RECORD_HEADER_BYTES) return;

        const view = new DataView(this.rx.buffer, this.rx.byteOffset + this.rxOffset, available);
        const type = view.getUint8(0);
        const len = view.getUint32(1, true);
        if (len > MAX_RECORD_BYTES) {
            Log.Info("Audio record too large");
            this.streamBroken = true;
            return;
        }
        if (available < RECORD_HEADER_BYTES + len) return;

        const payloadStart = this.rxOffset + RECORD_HEADER_BYTES;
        if (type == 0) {
            this.pushPcm(this.rx.subarray(payloadStart, payloadStart + len));
        }
        else if (type == 1 && len == 4) {
            this.applyGap(view.getUint32(RECORD_HEADER_BYTES, true));
        }

        this.rxOffset += RECORD_HEADER_BYTES + len;
    }
}

PCMPlayer.prototype.feed = function(data) {
    if (data.constructor != ArrayBuffer) return;
    if (data.byteLength == 0) return;

    // Ignore feed if player not started.
    if (!this.started) return;
    if (this.streamBroken) return;

    this.appendRx(data);
    this.parseRx();
    if (this.rxOffset === this.rx.length) {
        this.rx = EMPTY_RX;
        this.rxOffset = 0;
    }
}

PCMPlayer.prototype.flush = function() {
    if (!this.samplesBuffer) return;
    if (!this.samplesCount) return;
    if (this.samplesCount % this.option.channels != 0) return;

    const bufferSource = this.audioCtx.createBufferSource();
    const length = this.samplesCount / this.option.channels;
    const audioBuffer = this.audioCtx.createBuffer(this.option.channels, length, this.option.sampleRate);
    const audioLagMs = Math.floor((this.startTime - this.audioCtx.currentTime) * 1000);
    let forceClickingNoiseReduction = false;

    // Check if we missed our start time.
    if (audioLagMs < 0) {
        if (this.startTime != 0) {
            Log.Debug("Audio start time missed by " + Math.floor(audioLagMs * -1) + "ms");
        }
        forceClickingNoiseReduction = true;
        this.startTime = 0;
    }

    // Check if audio is lagging.
    if (audioLagMs > this.option.maxAudioLag) {
        Log.Debug("Too much audio lag: " + audioLagMs + "ms");
        forceClickingNoiseReduction = true
        this.startTime = 0;
    }

    // Copy our samples to the audio buffer.
    for (let channel = 0; channel < this.option.channels; channel++) {
        const audioData = audioBuffer.getChannelData(channel);
        let offset = channel;
        let decrement = 50;
        for (let i = 0; i < length; i++) {
            audioData[i] = this.samplesBuffer[offset];
            offset += this.option.channels;

            // Workaround to help reduce clicking noise.
            // https://github.com/samirkumardas/pcm-player/issues/4
            if (forceClickingNoiseReduction || this.option.reduceClickingNoise) {
                /* fadein */
                if (i < 50) {
                    audioData[i] =  (audioData[i] * i) / 50;
                }
                /* fadeout*/
                if (i >= (length - 51)) {
                    audioData[i] =  (audioData[i] * decrement--) / 50;
                }
            }
        }
    }

    if (this.startTime == 0) {
        this.startTime = this.audioCtx.currentTime + 0.005;
    }

    // Play the audio buffer at scheduled time.
    bufferSource.buffer = audioBuffer;
    bufferSource.connect(this.gainNode);
    bufferSource.start(this.startTime);

    // Set the start time for the next flush.
    this.startTime += audioBuffer.duration;
};

export default PCMPlayer;
