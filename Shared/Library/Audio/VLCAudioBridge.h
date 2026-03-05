#import <Foundation/Foundation.h>

@class VLCMediaPlayer;
@class SpectrumData;

NS_ASSUME_NONNULL_BEGIN

/// Objective-C bridge that installs libvlc audio callbacks on a VLCMediaPlayer,
/// re-injects PCM into AVAudioEngine for speaker output, and runs an FFT to
/// populate SpectrumData for visualization.
@interface VLCAudioBridge : NSObject

/// Set up audio callbacks on the given player.  Must be called BEFORE mediaPlayer.play().
/// @param player  The VLCMediaPlayer whose audio we intercept.
/// @param spectrum  A SpectrumData instance whose bins will be updated from the audio thread.
- (instancetype)initWithPlayer:(VLCMediaPlayer *)player
                  spectrumData:(SpectrumData *)spectrum;

/// Tear down the audio engine and release resources.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
