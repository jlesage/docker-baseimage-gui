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
        bitDepth: 16,
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

PCMPlayer.prototype.init = function(option) {
    var defaults = {
        encoding: '16bitIntLE',
        channels: 2,
        sampleRate: 44100,
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

    // Initialize samples array.
    const samplesBufferLength = Math.floor(this.option.bufferAudioTime * this.option.sampleRate / 1000) * this.option.channels;
    this.samplesBuffer = new Float32Array(samplesBufferLength);
    this.samplesCount = 0;

    // Setup the audio context.
    this.createAudioContext();
};

PCMPlayer.prototype.initLogging = function(level) {
    Log.initLogging(level)
}

PCMPlayer.prototype.createAudioContext = function() {
    this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();

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
    this.gainNode.gain.value = 1;
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
}

PCMPlayer.prototype.stop = function() {
    if (!this.started) return;
    this.started = false;
}

PCMPlayer.prototype.volume = function(volume) {
    if (!this.started) return;
    if (volume < 0 || volume > 1) return;
    this.gainNode.gain.value = volume;
};

PCMPlayer.prototype.destroy = function() {
    this.stop();
    this.destroyAudioContext();
};

PCMPlayer.prototype.feed = function(data) {
    if (data.constructor != ArrayBuffer) return;
    if (data.byteLength == 0) return;

    // Ignore feed if player not started.
    if (!this.started) return;

    // Ignore feed while the audio context is not running.
    if (this.audioCtx.state != 'running') return;

    // Make sure the data is aligned on a sample size boundary.
    if (data.byteLength % this.encodingDefs.sampleSize != 0) {
        this.startTime = 0;
        return;
    }

    // Create a view for data to work on.
    const dataView = new DataView(data);

    // Get the number of samples in data.
    const numSamples = dataView.byteLength / this.encodingDefs.sampleSize;

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

PCMPlayer.prototype.flush = function() {
    if (!this.samplesBuffer) return;
    if (!this.samplesBuffer.length) return;

    const bufferSource = this.audioCtx.createBufferSource();
    const length = this.samplesBuffer.length / this.option.channels;
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
