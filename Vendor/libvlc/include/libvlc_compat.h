// Minimal libvlc 3.x API declarations matching the installed VLC 3.0.21 dylib.
// Only includes the functions we actually use.
#ifndef LIBVLC_COMPAT_H
#define LIBVLC_COMPAT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;
typedef struct libvlc_renderer_discoverer_t libvlc_renderer_discoverer_t;
typedef struct libvlc_renderer_item_t libvlc_renderer_item_t;

typedef enum {
    libvlc_NothingSpecial = 0,
    libvlc_Opening,
    libvlc_Buffering,
    libvlc_Playing,
    libvlc_Paused,
    libvlc_Stopped,
    libvlc_Ended,
    libvlc_Error
} libvlc_state_t;

// Core
libvlc_instance_t *libvlc_new(int argc, const char *const *argv);
void libvlc_release(libvlc_instance_t *p_instance);

// Media
libvlc_media_t *libvlc_media_new_path(libvlc_instance_t *p_instance, const char *path);
void libvlc_media_release(libvlc_media_t *p_md);
void libvlc_media_parse(libvlc_media_t *p_md);
int64_t libvlc_media_get_duration(libvlc_media_t *p_md);

// Media Player
libvlc_media_player_t *libvlc_media_player_new_from_media(libvlc_media_t *p_md);
void libvlc_media_player_release(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_nsobject(libvlc_media_player_t *p_mi, void *drawable);
int libvlc_media_player_play(libvlc_media_player_t *p_mi);
void libvlc_media_player_pause(libvlc_media_player_t *p_mi);
void libvlc_media_player_stop(libvlc_media_player_t *p_mi);
int64_t libvlc_media_player_get_time(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_time(libvlc_media_player_t *p_mi, int64_t i_time);
float libvlc_media_player_get_position(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_position(libvlc_media_player_t *p_mi, float f_pos);
int64_t libvlc_media_player_get_length(libvlc_media_player_t *p_mi);
float libvlc_media_player_get_rate(libvlc_media_player_t *p_mi);
int libvlc_media_player_set_rate(libvlc_media_player_t *p_mi, float rate);
libvlc_state_t libvlc_media_player_get_state(libvlc_media_player_t *p_mi);
int libvlc_video_get_size(libvlc_media_player_t *p_mi, unsigned num, unsigned *px, unsigned *py);

// Audio
int libvlc_audio_get_volume(libvlc_media_player_t *p_mi);
int libvlc_audio_set_volume(libvlc_media_player_t *p_mi, int i_volume);
int libvlc_audio_get_mute(libvlc_media_player_t *p_mi);
void libvlc_audio_set_mute(libvlc_media_player_t *p_mi, int status);

// Audio delay (microseconds)
int64_t libvlc_audio_get_delay(libvlc_media_player_t *p_mi);
int libvlc_audio_set_delay(libvlc_media_player_t *p_mi, int64_t i_delay);

// Audio equalizer
typedef struct libvlc_equalizer_t libvlc_equalizer_t;

unsigned libvlc_audio_equalizer_get_preset_count(void);
const char *libvlc_audio_equalizer_get_preset_name(unsigned u_index);
unsigned libvlc_audio_equalizer_get_band_count(void);
float libvlc_audio_equalizer_get_band_frequency(unsigned u_index);

libvlc_equalizer_t *libvlc_audio_equalizer_new(void);
libvlc_equalizer_t *libvlc_audio_equalizer_new_from_preset(unsigned u_index);
void libvlc_audio_equalizer_release(libvlc_equalizer_t *p_equalizer);

int libvlc_audio_equalizer_set_preamp(libvlc_equalizer_t *p_eq, float f_preamp);
float libvlc_audio_equalizer_get_preamp(libvlc_equalizer_t *p_eq);
int libvlc_audio_equalizer_set_amp_at_index(libvlc_equalizer_t *p_eq, float f_amp, unsigned u_band);
float libvlc_audio_equalizer_get_amp_at_index(libvlc_equalizer_t *p_eq, unsigned u_band);

int libvlc_media_player_set_equalizer(libvlc_media_player_t *p_mi, libvlc_equalizer_t *p_eq);

// Track descriptions (linked list)
typedef struct libvlc_track_description_t {
    int i_id;
    char *psz_name;
    struct libvlc_track_description_t *p_next;
} libvlc_track_description_t;

void libvlc_track_description_list_release(libvlc_track_description_t *p_track_description);

// Audio tracks
int libvlc_audio_get_track_count(libvlc_media_player_t *p_mi);
libvlc_track_description_t *libvlc_audio_get_track_description(libvlc_media_player_t *p_mi);
int libvlc_audio_get_track(libvlc_media_player_t *p_mi);
int libvlc_audio_set_track(libvlc_media_player_t *p_mi, int i_track);

// Video tracks
int libvlc_video_get_track_count(libvlc_media_player_t *p_mi);
libvlc_track_description_t *libvlc_video_get_track_description(libvlc_media_player_t *p_mi);
int libvlc_video_get_track(libvlc_media_player_t *p_mi);
int libvlc_video_set_track(libvlc_media_player_t *p_mi, int i_track);

// Subtitle (SPU) tracks
int libvlc_video_get_spu_count(libvlc_media_player_t *p_mi);
libvlc_track_description_t *libvlc_video_get_spu_description(libvlc_media_player_t *p_mi);
int libvlc_video_get_spu(libvlc_media_player_t *p_mi);
int libvlc_video_set_spu(libvlc_media_player_t *p_mi, int i_spu);
int libvlc_video_set_subtitle_file(libvlc_media_player_t *p_mi, const char *psz_subtitle);

// Subtitle delay (microseconds)
int64_t libvlc_video_get_spu_delay(libvlc_media_player_t *p_mi);
int libvlc_video_set_spu_delay(libvlc_media_player_t *p_mi, int64_t i_delay);

// Deinterlace
void libvlc_video_set_deinterlace(libvlc_media_player_t *p_mi, const char *psz_mode);

// Video adjustments
enum {
    libvlc_adjust_Enable = 0,
    libvlc_adjust_Contrast,
    libvlc_adjust_Brightness,
    libvlc_adjust_Hue,
    libvlc_adjust_Saturation,
    libvlc_adjust_Gamma
};

int libvlc_video_get_adjust_int(libvlc_media_player_t *p_mi, unsigned option);
void libvlc_video_set_adjust_int(libvlc_media_player_t *p_mi, unsigned option, int value);
float libvlc_video_get_adjust_float(libvlc_media_player_t *p_mi, unsigned option);
void libvlc_video_set_adjust_float(libvlc_media_player_t *p_mi, unsigned option, float value);

// Video aspect ratio / crop
char *libvlc_video_get_aspect_ratio(libvlc_media_player_t *p_mi);
void libvlc_video_set_aspect_ratio(libvlc_media_player_t *p_mi, const char *psz_aspect);
char *libvlc_video_get_crop_geometry(libvlc_media_player_t *p_mi);
void libvlc_video_set_crop_geometry(libvlc_media_player_t *p_mi, const char *psz_geometry);
float libvlc_video_get_scale(libvlc_media_player_t *p_mi);
void libvlc_video_set_scale(libvlc_media_player_t *p_mi, float f_factor);

// Snapshot
int libvlc_video_take_snapshot(libvlc_media_player_t *p_mi, unsigned num,
                               const char *psz_filepath, unsigned int i_width, unsigned int i_height);

// Frame stepping
void libvlc_media_player_next_frame(libvlc_media_player_t *p_mi);

// Event manager
typedef struct libvlc_event_manager_t libvlc_event_manager_t;
typedef int64_t libvlc_time_t;

typedef struct libvlc_event_t {
    int type;
    void *p_obj;
    union {
        struct { float new_cache; } media_player_buffering;
        struct { double new_position; } media_player_position_changed;
        struct { libvlc_time_t new_time; } media_player_time_changed;
        struct { libvlc_time_t new_length; } media_player_length_changed;
        struct { int new_count; } media_player_vout;
        struct { libvlc_renderer_item_t *item; } renderer_discoverer_item_added;
        struct { libvlc_renderer_item_t *item; } renderer_discoverer_item_deleted;
    } u;
} libvlc_event_t;

enum {
    libvlc_MediaPlayerPlaying       = 0x100 + 4,
    libvlc_MediaPlayerPaused        = 0x100 + 5,
    libvlc_MediaPlayerStopped       = 0x100 + 6,
    libvlc_MediaPlayerTimeChanged   = 0x100 + 11,
    libvlc_MediaPlayerPositionChanged = 0x100 + 12,
    libvlc_MediaPlayerLengthChanged = 0x100 + 17,
    libvlc_MediaPlayerEndReached    = 0x100 + 9,
    libvlc_RendererDiscovererItemAdded   = 0x502,
    libvlc_RendererDiscovererItemDeleted = 0x503,
};

typedef void (*libvlc_callback_t)(const libvlc_event_t *, void *);

libvlc_event_manager_t *libvlc_media_player_event_manager(libvlc_media_player_t *p_mi);
int libvlc_event_attach(libvlc_event_manager_t *p_event_manager, int i_event_type,
                        libvlc_callback_t f_callback, void *user_data);
void libvlc_event_detach(libvlc_event_manager_t *p_event_manager, int i_event_type,
                         libvlc_callback_t f_callback, void *user_data);

// Chapter navigation
int libvlc_media_player_get_chapter_count(libvlc_media_player_t *p_mi);
int libvlc_media_player_get_chapter(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_chapter(libvlc_media_player_t *p_mi, int i_chapter);

// Audio filters (via media options)
void libvlc_media_add_option(libvlc_media_t *p_md, const char *psz_options);

// Renderer discoverer
typedef struct libvlc_rd_description_t {
    char *psz_name;
    char *psz_longname;
} libvlc_rd_description_t;

libvlc_renderer_item_t *libvlc_renderer_item_hold(libvlc_renderer_item_t *p_item);
void libvlc_renderer_item_release(libvlc_renderer_item_t *p_item);
const char *libvlc_renderer_item_name(const libvlc_renderer_item_t *p_item);
const char *libvlc_renderer_item_type(const libvlc_renderer_item_t *p_item);
int libvlc_renderer_item_flags(const libvlc_renderer_item_t *p_item);

libvlc_renderer_discoverer_t *libvlc_renderer_discoverer_new(libvlc_instance_t *p_inst, const char *psz_name);
void libvlc_renderer_discoverer_release(libvlc_renderer_discoverer_t *p_rd);
int libvlc_renderer_discoverer_start(libvlc_renderer_discoverer_t *p_rd);
void libvlc_renderer_discoverer_stop(libvlc_renderer_discoverer_t *p_rd);
libvlc_event_manager_t *libvlc_renderer_discoverer_event_manager(libvlc_renderer_discoverer_t *p_rd);
size_t libvlc_renderer_discoverer_list_get(libvlc_instance_t *p_inst, libvlc_rd_description_t ***ppp_services);
void libvlc_renderer_discoverer_list_release(libvlc_rd_description_t **pp_services, size_t i_count);

int libvlc_media_player_set_renderer(libvlc_media_player_t *p_mi, libvlc_renderer_item_t *p_item);

// External subtitle/audio slave
typedef enum libvlc_media_slave_type_t {
    libvlc_media_slave_type_subtitle = 0,
    libvlc_media_slave_type_audio
} libvlc_media_slave_type_t;

int libvlc_media_player_add_slave(libvlc_media_player_t *p_mi,
                                  libvlc_media_slave_type_t i_type,
                                  const char *psz_uri, int b_select);

#ifdef __cplusplus
}
#endif

#endif
