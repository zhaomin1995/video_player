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

@interface FFmpegBridge : NSObject

+ (void)initialize;
+ (DVPMediaProbeResult)probeFile:(NSString *)path;
+ (nullable NSString *)videoCodecNameForFile:(NSString *)path;
+ (NSArray<NSDictionary *> *)audioTracksForFile:(NSString *)path;
+ (NSArray<NSDictionary *> *)subtitleTracksForFile:(NSString *)path;

// Remuxing: MKV -> MP4 (full remux with audio transcoding if needed)
+ (BOOL)remuxFile:(NSString *)inputPath
       toOutput:(NSString *)outputPath
          error:(NSError **)error;

// Subtitle extraction
+ (nullable NSString *)extractSubtitleTrack:(int)trackIndex
                                   fromFile:(NSString *)path
                                      error:(NSError **)error;

// Chapter extraction
+ (NSArray<NSDictionary *> *)chaptersForFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
