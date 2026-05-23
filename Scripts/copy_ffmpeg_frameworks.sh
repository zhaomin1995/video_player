#!/bin/bash
# Xcode Run Script Build Phase: Copy FFmpeg dylibs to app bundle
set -e

FFMPEG_LIB_DIR="${PROJECT_DIR}/Vendor/ffmpeg/lib"
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ ! -d "$FFMPEG_LIB_DIR" ]; then
    echo "warning: FFmpeg not built. Run Scripts/build_ffmpeg.sh first."
    exit 0
fi

mkdir -p "$FRAMEWORKS_DIR"

for dylib in libavformat libavcodec libavutil libswresample libswscale; do
    # Find the versioned dylib (not the symlink)
    SRC=$(find "$FFMPEG_LIB_DIR" -name "${dylib}.*.*.*.dylib" -not -type l | head -1)
    if [ -n "$SRC" ]; then
        cp -f "$SRC" "$FRAMEWORKS_DIR/"
        BASENAME=$(basename "$SRC")
        # Create version symlink
        SHORTNAME=$(echo "$BASENAME" | sed 's/\([^.]*\.[0-9]*\)\..*/\1.dylib/')
        ln -sf "$BASENAME" "$FRAMEWORKS_DIR/$SHORTNAME" 2>/dev/null || true
        ln -sf "$BASENAME" "$FRAMEWORKS_DIR/${dylib}.dylib" 2>/dev/null || true
    fi
done

echo "FFmpeg dylibs copied to $FRAMEWORKS_DIR"
