#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int videoCodecId;
    int audioCodecId;
    int width;
    int height;
    double duration;
    int audioChannels;
    int audioSampleRate;
    int numAudioTracks;
    int numSubtitleTracks;
    BOOL hasDolbyVision;
    BOOL hasHDR;
} DVPMediaProbeResult;

typedef struct {
    int trackIndex;
    char language[32];
    char codecName[32];
    int channels;
    int sampleRate;
} DVPAudioTrackInfo;

typedef struct {
    int trackIndex;
    char language[32];
    char codecName[32];
} DVPSubtitleTrackInfo;

@interface FFmpegBridge : NSObject

+ (void)initialize;
+ (DVPMediaProbeResult)probeFile:(NSString *)path;
+ (NSArray<NSDictionary *> *)audioTracksForFile:(NSString *)path;
+ (NSArray<NSDictionary *> *)subtitleTracksForFile:(NSString *)path;

// Remuxing: MKV -> fragmented MP4
+ (BOOL)remuxFile:(NSString *)inputPath
       toOutput:(NSString *)outputPath
          error:(NSError **)error;

// Subtitle extraction
+ (nullable NSString *)extractSubtitleTrack:(int)trackIndex
                                   fromFile:(NSString *)path
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
