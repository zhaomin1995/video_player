#import "FFmpegBridge.h"

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libavutil/dict.h"
#include "libavutil/channel_layout.h"
#include "libavutil/opt.h"
#include "libswresample/swresample.h"

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

static BOOL isAudioCodecMP4Compatible(enum AVCodecID codec_id) {
    return codec_id == AV_CODEC_ID_AAC ||
           codec_id == AV_CODEC_ID_AC3 ||
           codec_id == AV_CODEC_ID_EAC3 ||
           codec_id == AV_CODEC_ID_MP3 ||
           codec_id == AV_CODEC_ID_ALAC ||
           codec_id == AV_CODEC_ID_FLAC ||
           codec_id == AV_CODEC_ID_OPUS;
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
    int audio_transcode_stream = -1; // input stream index that needs transcoding
    int stream_index = 0;

    AVCodecContext *dec_ctx = NULL, *enc_ctx = NULL;

    for (unsigned i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVCodecParameters *codecpar = ifmt_ctx->streams[i]->codecpar;
        if (codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
            codecpar->codec_type != AVMEDIA_TYPE_AUDIO) {
            stream_mapping[i] = -1;
            continue;
        }

        stream_mapping[i] = stream_index++;
        AVStream *out_stream = avformat_new_stream(ofmt_ctx, NULL);

        if (codecpar->codec_type == AVMEDIA_TYPE_AUDIO && !isAudioCodecMP4Compatible(codecpar->codec_id)) {
            // Transcode to AAC
            NSLog(@"[FFmpegBridge] Audio codec %d not MP4-compatible, transcoding to AAC", codecpar->codec_id);
            audio_transcode_stream = i;

            // Setup decoder
            const AVCodec *decoder = avcodec_find_decoder(codecpar->codec_id);
            if (!decoder) {
                NSLog(@"[FFmpegBridge] No decoder for codec %d", codecpar->codec_id);
                stream_mapping[i] = -1;
                stream_index--;
                continue;
            }
            dec_ctx = avcodec_alloc_context3(decoder);
            avcodec_parameters_to_context(dec_ctx, codecpar);
            avcodec_open2(dec_ctx, decoder, NULL);

            // Setup AAC encoder
            const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_AAC);
            if (!encoder) {
                NSLog(@"[FFmpegBridge] No AAC encoder found");
                avcodec_free_context(&dec_ctx);
                stream_mapping[i] = -1;
                stream_index--;
                continue;
            }
            enc_ctx = avcodec_alloc_context3(encoder);
            enc_ctx->sample_rate = codecpar->sample_rate;
            enc_ctx->bit_rate = 128000;
            av_channel_layout_default(&enc_ctx->ch_layout, codecpar->ch_layout.nb_channels);
            enc_ctx->sample_fmt = encoder->sample_fmts ? encoder->sample_fmts[0] : AV_SAMPLE_FMT_FLTP;
            enc_ctx->time_base = (AVRational){1, codecpar->sample_rate};
            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
                enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
            avcodec_open2(enc_ctx, encoder, NULL);
            avcodec_parameters_from_context(out_stream->codecpar, enc_ctx);
            out_stream->time_base = enc_ctx->time_base;
        } else {
            avcodec_parameters_copy(out_stream->codecpar, codecpar);
            out_stream->codecpar->codec_tag = 0;
        }
    }

    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, [outputPath UTF8String], AVIO_FLAG_WRITE);
        if (ret < 0) {
            free(stream_mapping);
            if (dec_ctx) avcodec_free_context(&dec_ctx);
            if (enc_ctx) avcodec_free_context(&enc_ctx);
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
        if (dec_ctx) avcodec_free_context(&dec_ctx);
        if (enc_ctx) avcodec_free_context(&enc_ctx);
        avformat_close_input(&ifmt_ctx);
        avio_closep(&ofmt_ctx->pb);
        avformat_free_context(ofmt_ctx);
        return NO;
    }

    // Setup resampler for audio transcoding if needed
    struct SwrContext *swr_ctx = NULL;
    if (dec_ctx && enc_ctx) {
        swr_alloc_set_opts2(&swr_ctx,
                            &enc_ctx->ch_layout, enc_ctx->sample_fmt, enc_ctx->sample_rate,
                            &dec_ctx->ch_layout, dec_ctx->sample_fmt, dec_ctx->sample_rate,
                            0, NULL);
        swr_init(swr_ctx);
    }

    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    AVPacket *enc_pkt = av_packet_alloc();

    while (av_read_frame(ifmt_ctx, pkt) >= 0) {
        if (pkt->stream_index >= (int)ifmt_ctx->nb_streams ||
            stream_mapping[pkt->stream_index] < 0) {
            av_packet_unref(pkt);
            continue;
        }

        int in_idx = pkt->stream_index;
        AVStream *in_stream = ifmt_ctx->streams[in_idx];
        pkt->stream_index = stream_mapping[in_idx];
        AVStream *out_stream = ofmt_ctx->streams[pkt->stream_index];

        if (in_idx == audio_transcode_stream && dec_ctx && enc_ctx) {
            // Decode -> resample -> encode
            ret = avcodec_send_packet(dec_ctx, pkt);
            av_packet_unref(pkt);
            while (ret >= 0) {
                ret = avcodec_receive_frame(dec_ctx, frame);
                if (ret < 0) break;

                // Resample
                AVFrame *resampled = av_frame_alloc();
                resampled->sample_rate = enc_ctx->sample_rate;
                resampled->format = enc_ctx->sample_fmt;
                av_channel_layout_copy(&resampled->ch_layout, &enc_ctx->ch_layout);
                resampled->nb_samples = swr_get_out_samples(swr_ctx, frame->nb_samples);
                av_frame_get_buffer(resampled, 0);
                swr_convert(swr_ctx, resampled->data, resampled->nb_samples,
                           (const uint8_t **)frame->data, frame->nb_samples);
                resampled->pts = frame->pts;

                avcodec_send_frame(enc_ctx, resampled);
                av_frame_free(&resampled);

                while (avcodec_receive_packet(enc_ctx, enc_pkt) >= 0) {
                    enc_pkt->stream_index = pkt->stream_index;
                    av_packet_rescale_ts(enc_pkt, enc_ctx->time_base, out_stream->time_base);
                    enc_pkt->stream_index = stream_mapping[in_idx];
                    av_interleaved_write_frame(ofmt_ctx, enc_pkt);
                    av_packet_unref(enc_pkt);
                }
                av_frame_unref(frame);
            }
        } else {
            // Copy packet (video or compatible audio)
            pkt->pts = av_rescale_q_rnd(pkt->pts, in_stream->time_base, out_stream->time_base,
                                         AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
            pkt->dts = av_rescale_q_rnd(pkt->dts, in_stream->time_base, out_stream->time_base,
                                         AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
            pkt->duration = av_rescale_q(pkt->duration, in_stream->time_base, out_stream->time_base);
            pkt->pos = -1;
            av_interleaved_write_frame(ofmt_ctx, pkt);
            av_packet_unref(pkt);
        }
    }

    // Flush encoder
    if (enc_ctx) {
        avcodec_send_frame(enc_ctx, NULL);
        while (avcodec_receive_packet(enc_ctx, enc_pkt) >= 0) {
            enc_pkt->stream_index = stream_mapping[audio_transcode_stream];
            AVStream *out_stream = ofmt_ctx->streams[enc_pkt->stream_index];
            av_packet_rescale_ts(enc_pkt, enc_ctx->time_base, out_stream->time_base);
            av_interleaved_write_frame(ofmt_ctx, enc_pkt);
            av_packet_unref(enc_pkt);
        }
    }

    av_packet_free(&pkt);
    av_packet_free(&enc_pkt);
    av_frame_free(&frame);
    av_write_trailer(ofmt_ctx);
    free(stream_mapping);

    if (swr_ctx) swr_free(&swr_ctx);
    if (dec_ctx) avcodec_free_context(&dec_ctx);
    if (enc_ctx) avcodec_free_context(&enc_ctx);

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
