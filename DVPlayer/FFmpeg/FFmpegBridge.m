#import "FFmpegBridge.h"

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libavutil/dict.h"

#define HAS_FFMPEG 1

@implementation FFmpegBridge

+ (void)initialize {
#if HAS_FFMPEG
    // FFmpeg 7.x doesn't need av_register_all()
#endif
}

+ (DVPMediaProbeResult)probeFile:(NSString *)path {
    DVPMediaProbeResult result = {0};

#if HAS_FFMPEG
    AVFormatContext *fmt_ctx = NULL;
    int ret = avformat_open_input(&fmt_ctx, [path UTF8String], NULL, NULL);
    if (ret < 0) return result;

    avformat_find_stream_info(fmt_ctx, NULL);

    result.duration = (double)fmt_ctx->duration / AV_TIME_BASE;

    for (unsigned i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        AVCodecParameters *codecpar = stream->codecpar;

        if (codecpar->codec_type == AVMEDIA_TYPE_VIDEO && result.videoCodecId == 0) {
            result.videoCodecId = codecpar->codec_id;
            result.width = codecpar->width;
            result.height = codecpar->height;

            // Check for Dolby Vision side data
            for (int j = 0; j < stream->nb_side_data; j++) {
                if (stream->side_data[j].type == AV_PKT_DATA_DOVI_CONF) {
                    result.hasDolbyVision = YES;
                }
            }

            // Check for HDR
            if (codecpar->color_trc == AVCOL_TRC_SMPTE2084 ||
                codecpar->color_trc == AVCOL_TRC_ARIB_STD_B67) {
                result.hasHDR = YES;
            }
        }

        if (codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (result.audioCodecId == 0) {
                result.audioCodecId = codecpar->codec_id;
                result.audioChannels = codecpar->ch_layout.nb_channels;
                result.audioSampleRate = codecpar->sample_rate;
            }
            result.numAudioTracks++;
        }

        if (codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            result.numSubtitleTracks++;
        }
    }

    avformat_close_input(&fmt_ctx);
#endif

    return result;
}

+ (NSArray<NSDictionary *> *)audioTracksForFile:(NSString *)path {
    NSMutableArray *tracks = [NSMutableArray array];

#if HAS_FFMPEG
    AVFormatContext *fmt_ctx = NULL;
    if (avformat_open_input(&fmt_ctx, [path UTF8String], NULL, NULL) < 0) return tracks;
    avformat_find_stream_info(fmt_ctx, NULL);

    int audioIndex = 0;
    for (unsigned i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        if (stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) continue;

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"index"] = @(audioIndex);
        info[@"streamIndex"] = @(i);

        const AVCodecDescriptor *desc = avcodec_descriptor_get(stream->codecpar->codec_id);
        if (desc) {
            info[@"codec"] = [NSString stringWithUTF8String:desc->name];
        }

        info[@"channels"] = @(stream->codecpar->ch_layout.nb_channels);
        info[@"sampleRate"] = @(stream->codecpar->sample_rate);

        const AVDictionaryEntry *lang = av_dict_get(stream->metadata, "language", NULL, 0);
        if (lang) {
            info[@"language"] = [NSString stringWithUTF8String:lang->value];
        }

        const AVDictionaryEntry *title = av_dict_get(stream->metadata, "title", NULL, 0);
        if (title) {
            info[@"title"] = [NSString stringWithUTF8String:title->value];
        }

        [tracks addObject:info];
        audioIndex++;
    }

    avformat_close_input(&fmt_ctx);
#endif

    return tracks;
}

+ (NSArray<NSDictionary *> *)subtitleTracksForFile:(NSString *)path {
    NSMutableArray *tracks = [NSMutableArray array];

#if HAS_FFMPEG
    AVFormatContext *fmt_ctx = NULL;
    if (avformat_open_input(&fmt_ctx, [path UTF8String], NULL, NULL) < 0) return tracks;
    avformat_find_stream_info(fmt_ctx, NULL);

    int subIndex = 0;
    for (unsigned i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        if (stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) continue;

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"index"] = @(subIndex);
        info[@"streamIndex"] = @(i);

        const AVCodecDescriptor *desc = avcodec_descriptor_get(stream->codecpar->codec_id);
        if (desc) {
            info[@"codec"] = [NSString stringWithUTF8String:desc->name];
        }

        const AVDictionaryEntry *lang = av_dict_get(stream->metadata, "language", NULL, 0);
        if (lang) {
            info[@"language"] = [NSString stringWithUTF8String:lang->value];
        }

        const AVDictionaryEntry *title = av_dict_get(stream->metadata, "title", NULL, 0);
        if (title) {
            info[@"title"] = [NSString stringWithUTF8String:title->value];
        }

        [tracks addObject:info];
        subIndex++;
    }

    avformat_close_input(&fmt_ctx);
#endif

    return tracks;
}

+ (BOOL)remuxFile:(NSString *)inputPath
       toOutput:(NSString *)outputPath
          error:(NSError **)error {
#if HAS_FFMPEG
    NSLog(@"[FFmpegBridge] Remuxing: %@ -> %@", inputPath, outputPath);
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    int ret;

    ret = avformat_open_input(&ifmt_ctx, [inputPath UTF8String], NULL, NULL);
    if (ret < 0) {
        NSLog(@"[FFmpegBridge] Failed to open input: %d", ret);
        if (error) *error = [NSError errorWithDomain:@"FFmpeg" code:ret userInfo:@{NSLocalizedDescriptionKey: @"Failed to open input"}];
        return NO;
    }

    avformat_find_stream_info(ifmt_ctx, NULL);

    avformat_alloc_output_context2(&ofmt_ctx, NULL, "mp4", [outputPath UTF8String]);
    if (!ofmt_ctx) {
        avformat_close_input(&ifmt_ctx);
        return NO;
    }

    int *stream_mapping = calloc(ifmt_ctx->nb_streams, sizeof(int));
    int stream_index = 0;

    for (unsigned i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVCodecParameters *codecpar = ifmt_ctx->streams[i]->codecpar;
        if (codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
            codecpar->codec_type != AVMEDIA_TYPE_AUDIO) {
            stream_mapping[i] = -1;
            continue;
        }

        stream_mapping[i] = stream_index++;

        AVStream *out_stream = avformat_new_stream(ofmt_ctx, NULL);
        avcodec_parameters_copy(out_stream->codecpar, codecpar);
        out_stream->codecpar->codec_tag = 0;
    }

    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, [outputPath UTF8String], AVIO_FLAG_WRITE);
        if (ret < 0) {
            free(stream_mapping);
            avformat_close_input(&ifmt_ctx);
            avformat_free_context(ofmt_ctx);
            return NO;
        }
    }

    AVDictionary *opts = NULL;
    av_dict_set(&opts, "movflags", "faststart", 0);

    ret = avformat_write_header(ofmt_ctx, &opts);
    av_dict_free(&opts);
    if (ret < 0) {
        free(stream_mapping);
        avformat_close_input(&ifmt_ctx);
        avio_closep(&ofmt_ctx->pb);
        avformat_free_context(ofmt_ctx);
        return NO;
    }

    AVPacket *pkt = av_packet_alloc();
    while (av_read_frame(ifmt_ctx, pkt) >= 0) {
        if (pkt->stream_index >= (int)ifmt_ctx->nb_streams ||
            stream_mapping[pkt->stream_index] < 0) {
            av_packet_unref(pkt);
            continue;
        }

        AVStream *in_stream = ifmt_ctx->streams[pkt->stream_index];
        pkt->stream_index = stream_mapping[pkt->stream_index];
        AVStream *out_stream = ofmt_ctx->streams[pkt->stream_index];

        pkt->pts = av_rescale_q_rnd(pkt->pts, in_stream->time_base, out_stream->time_base,
                                     AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
        pkt->dts = av_rescale_q_rnd(pkt->dts, in_stream->time_base, out_stream->time_base,
                                     AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
        pkt->duration = av_rescale_q(pkt->duration, in_stream->time_base, out_stream->time_base);
        pkt->pos = -1;

        av_interleaved_write_frame(ofmt_ctx, pkt);
        av_packet_unref(pkt);
    }

    av_packet_free(&pkt);
    av_write_trailer(ofmt_ctx);
    free(stream_mapping);

    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE))
        avio_closep(&ofmt_ctx->pb);

    avformat_close_input(&ifmt_ctx);
    avformat_free_context(ofmt_ctx);

    NSLog(@"[FFmpegBridge] Remux complete: %@", outputPath);
    return YES;
#else
    if (error) *error = [NSError errorWithDomain:@"FFmpeg" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"FFmpeg not linked"}];
    return NO;
#endif
}

+ (nullable NSString *)extractSubtitleTrack:(int)trackIndex
                                   fromFile:(NSString *)path
                                      error:(NSError **)error {
    // TODO: Extract subtitle track as text
    return nil;
}

@end
