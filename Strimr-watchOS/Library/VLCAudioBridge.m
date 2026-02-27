#import "VLCAudioBridge.h"

#import <VLCKit/VLCMediaPlayer.h>

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <os/lock.h>

// ---------------------------------------------------------------------------
// Forward-declare the libvlc C types and functions we need.
// Importing the vlc/ C headers directly causes include-path / redefinition
// issues outside the VLCKit module, so we just declare what we use.
// ---------------------------------------------------------------------------
typedef struct libvlc_media_player_t libvlc_media_player_t;

typedef void (*libvlc_audio_play_cb)(void *data, const void *samples,
                                     unsigned count, int64_t pts);
typedef void (*libvlc_audio_pause_cb)(void *data, int64_t pts);
typedef void (*libvlc_audio_resume_cb)(void *data, int64_t pts);
typedef void (*libvlc_audio_flush_cb)(void *data, int64_t pts);
typedef void (*libvlc_audio_drain_cb)(void *data);

extern void libvlc_audio_set_format(libvlc_media_player_t *mp,
                                    const char *format,
                                    unsigned rate, unsigned channels);
extern void libvlc_audio_set_callbacks(libvlc_media_player_t *mp,
                                       libvlc_audio_play_cb play,
                                       libvlc_audio_pause_cb pause,
                                       libvlc_audio_resume_cb resume,
                                       libvlc_audio_flush_cb flush,
                                       libvlc_audio_drain_cb drain,
                                       void *opaque);

extern int libvlc_audio_output_set(libvlc_media_player_t *mp,
                                   const char *psz_name);

// Redeclare the Internal category locally so we can access playerInstance
// without importing PrivateHeaders (which causes header-search conflicts).
@interface VLCMediaPlayer (InternalAccess)
@property (readonly) libvlc_media_player_t *playerInstance;
@end

// ---------------------------------------------------------------------------
// Forward-declare the Swift SpectrumData class so we can call it from ObjC.
// The bridging header makes the Swift class visible, but we also need the
// watchOS target module header.  We import it via the auto-generated header.
// ---------------------------------------------------------------------------
#if __has_include("Strimr_watchOS-Swift.h")
#import "Strimr_watchOS-Swift.h"
#elif __has_include("Strimr-watchOS-Swift.h")
#import "Strimr-watchOS-Swift.h"
#endif

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
static const unsigned int kSampleRate   = 44100;
static const unsigned int kChannels     = 2;
static const int          kFFTSize      = 1024;  // samples per FFT window
static const int          kLog2N        = 10;    // log2(1024)
static const int          kDisplayBins  = 32;    // output bins for visualization

// ---------------------------------------------------------------------------
// Context passed through the libvlc opaque pointer.
// ---------------------------------------------------------------------------
typedef struct {
    // AVAudioEngine playback
    __unsafe_unretained AVAudioEngine      *engine;
    __unsafe_unretained AVAudioPlayerNode  *playerNode;
    __unsafe_unretained AVAudioFormat      *format;

    // FFT state (Accelerate)
    FFTSetup        fftSetup;
    float          *window;       // Hann window (kFFTSize)
    float          *fftInBuffer;  // windowed samples
    DSPSplitComplex splitComplex; // real/imag for FFT

    // Output spectrum → SpectrumData (Swift @Observable)
    __unsafe_unretained SpectrumData *spectrumData;
} AudioContext;

// ---------------------------------------------------------------------------
#pragma mark - C Callbacks
// ---------------------------------------------------------------------------

/// Called by VLC on its private audio thread each time a block of decoded
/// audio is ready.  `samples` is interleaved float32, `count` is the number
/// of frames (not bytes, not total samples).
static void play_cb(void *opaque, const void *samples, unsigned count, int64_t pts) {
    AudioContext *ctx = (AudioContext *)opaque;
    if (!ctx || !ctx->engine || !ctx->playerNode || !ctx->format) return;

    const float *floatSamples = (const float *)samples;
    const unsigned totalSamples = count * kChannels;

    // ------------------------------------------------------------------
    // 1. Re-inject audio into AVAudioEngine for speaker output
    // ------------------------------------------------------------------
    AVAudioFrameCount frameCount = (AVAudioFrameCount)count;
    AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:ctx->format
                                                                frameCapacity:frameCount];
    if (!pcmBuffer) return;
    pcmBuffer.frameLength = frameCount;

    // Deinterleave into the non-interleaved buffer that AVAudioPCMBuffer expects.
    float *left  = pcmBuffer.floatChannelData[0];
    float *right = pcmBuffer.floatChannelData[1];
    for (unsigned i = 0; i < count; i++) {
        left[i]  = floatSamples[i * 2];
        right[i] = floatSamples[i * 2 + 1];
    }

    [ctx->playerNode scheduleBuffer:pcmBuffer completionHandler:nil];

    // ------------------------------------------------------------------
    // 2. FFT on left channel (run on this VLC audio thread)
    // ------------------------------------------------------------------
    if (count < kFFTSize) return; // need at least one full window

    // Apply Hann window
    vDSP_vmul(left, 1, ctx->window, 1, ctx->fftInBuffer, 1, kFFTSize);

    // Pack real data into split complex form
    vDSP_ctoz((DSPComplex *)ctx->fftInBuffer, 2,
              &ctx->splitComplex, 1, kFFTSize / 2);

    // In-place FFT
    vDSP_fft_zrip(ctx->fftSetup, &ctx->splitComplex, 1, kLog2N, FFT_FORWARD);

    // Compute magnitudes (squared)
    float magnitudes[kFFTSize / 2];
    vDSP_zvmags(&ctx->splitComplex, 1, magnitudes, 1, kFFTSize / 2);

    // Convert to dB-ish scale and normalize
    const int halfFFT = kFFTSize / 2;  // 512 bins

    // Logarithmic bin grouping: map 512 FFT bins → 32 display bins.
    // Aggressive log curve (pow 2.5) packs resolution into musically active range.
    float displayBins[kDisplayBins];
    for (int b = 0; b < kDisplayBins; b++) {
        float startFrac = powf((float)b / (float)kDisplayBins, 2.5f);
        float endFrac   = powf((float)(b + 1) / (float)kDisplayBins, 2.5f);
        int startIdx = (int)(startFrac * halfFFT);
        int endIdx   = (int)(endFrac * halfFFT);
        if (endIdx <= startIdx) endIdx = startIdx + 1;
        if (endIdx > halfFFT)   endIdx = halfFFT;

        float sum = 0;
        for (int j = startIdx; j < endIdx; j++) {
            sum += magnitudes[j];
        }
        float avg = sum / (float)(endIdx - startIdx);

        // Sqrt to get magnitude from squared, then scale
        float mag = sqrtf(avg) / (float)(kFFTSize);

        // Frequency-dependent gain: boost higher bins progressively
        // (music has much less energy in treble, needs compensation)
        float binFrac = (float)b / (float)kDisplayBins;
        float gain = 12.0f + binFrac * 20.0f;  // 12× at bass, 32× at treble
        mag *= gain;
        if (mag > 1.0f) mag = 1.0f;
        if (mag < 0.0f) mag = 0.0f;

        displayBins[b] = mag;
    }

    // Write into SpectrumData (Swift object, lock-guarded internally)
    NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:kDisplayBins];
    for (int i = 0; i < kDisplayBins; i++) {
        [arr addObject:@(displayBins[i])];
    }

    // Convert to Swift [Float] via a temporary NSArray → bridging
    // SpectrumData.updateFromObjC() accepts [NSNumber]
    [ctx->spectrumData updateFromObjC:arr];
}

static void pause_cb(void *opaque, int64_t pts) {
    AudioContext *ctx = (AudioContext *)opaque;
    if (!ctx || !ctx->playerNode) return;
    [ctx->playerNode pause];
}

static void resume_cb(void *opaque, int64_t pts) {
    AudioContext *ctx = (AudioContext *)opaque;
    if (!ctx || !ctx->playerNode) return;
    [ctx->playerNode play];
}

static void flush_cb(void *opaque, int64_t pts) {
    AudioContext *ctx = (AudioContext *)opaque;
    if (!ctx || !ctx->playerNode) return;
    [ctx->playerNode stop];
    [ctx->playerNode play];
}

// ---------------------------------------------------------------------------
#pragma mark - VLCAudioBridge
// ---------------------------------------------------------------------------

@implementation VLCAudioBridge {
    AudioContext *_ctx;
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_playerNode;
    AVAudioFormat *_format;
}

- (instancetype)initWithPlayer:(VLCMediaPlayer *)player
                  spectrumData:(SpectrumData *)spectrum {
    self = [super init];
    if (!self) return nil;

    // --- AVAudioEngine setup ---
    _engine     = [[AVAudioEngine alloc] init];
    _playerNode = [[AVAudioPlayerNode alloc] init];
    _format     = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                  sampleRate:kSampleRate
                                                    channels:kChannels
                                                 interleaved:NO];

    [_engine attachNode:_playerNode];
    [_engine connect:_playerNode to:_engine.mainMixerNode format:_format];

    NSError *error = nil;
    [_engine startAndReturnError:&error];
    if (error) {
        NSLog(@"[VLCAudioBridge] AVAudioEngine start error: %@", error);
    }
    [_playerNode play];

    // --- Allocate FFT resources ---
    _ctx = (AudioContext *)calloc(1, sizeof(AudioContext));
    _ctx->engine       = _engine;
    _ctx->playerNode   = _playerNode;
    _ctx->format       = _format;
    _ctx->spectrumData = spectrum;

    _ctx->fftSetup = vDSP_create_fftsetup(kLog2N, FFT_RADIX2);

    _ctx->window      = (float *)calloc(kFFTSize, sizeof(float));
    vDSP_hann_window(_ctx->window, kFFTSize, vDSP_HANN_NORM);

    _ctx->fftInBuffer = (float *)calloc(kFFTSize, sizeof(float));

    _ctx->splitComplex.realp = (float *)calloc(kFFTSize / 2, sizeof(float));
    _ctx->splitComplex.imagp = (float *)calloc(kFFTSize / 2, sizeof(float));

    // --- Install libvlc audio callbacks ---
    libvlc_media_player_t *mp = [player playerInstance];

    // Force the "amem" audio output module — the default "avsamplebuffer" module
    // fails on watchOS (AVAudioEngine can't associate with audio session).
    libvlc_audio_output_set(mp, "amem");

    libvlc_audio_set_format(mp, "FL32", kSampleRate, kChannels);
    libvlc_audio_set_callbacks(mp,
                               play_cb,
                               pause_cb,
                               resume_cb,
                               flush_cb,
                               NULL,       // drain — not needed
                               _ctx);

    return self;
}

- (void)stop {
    if (_ctx) {
        // Free FFT resources
        if (_ctx->fftSetup) {
            vDSP_destroy_fftsetup(_ctx->fftSetup);
            _ctx->fftSetup = NULL;
        }
        free(_ctx->window);        _ctx->window = NULL;
        free(_ctx->fftInBuffer);   _ctx->fftInBuffer = NULL;
        free(_ctx->splitComplex.realp); _ctx->splitComplex.realp = NULL;
        free(_ctx->splitComplex.imagp); _ctx->splitComplex.imagp = NULL;
        free(_ctx);
        _ctx = NULL;
    }

    [_playerNode stop];
    [_engine stop];
    _playerNode = nil;
    _engine = nil;
}

- (void)dealloc {
    [self stop];
}

@end
