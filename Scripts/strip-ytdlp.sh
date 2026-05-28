#!/usr/bin/env bash
# Strips the bundled yt-dlp distribution down to what we actually need.
#
# The PyInstaller-packed yt-dlp_macos distribution ships with:
#   - every binary as universal (x86_64 + arm64), even though the app pins
#     ARCHS = arm64 in Release. The x86_64 slices are dead weight.
#   - curl_cffi + libcurl-impersonate (~28 MB), a browser-impersonation HTTP
#     client used to evade bot detection. yt-dlp falls back to urllib if
#     missing, which is fine for our format-listing + URL-extraction use case.
#   - tiny optional helpers (setuptools, websockets) that aren't loaded for
#     YouTube extraction.
#
# Net: ~145 MB → ~69 MB with zero behavioral change on YouTube URLs.
#
# Idempotent: re-running on already-stripped tree is a no-op (lipo skips
# single-arch, rm -f tolerates missing files).
#
# Usage:
#   Scripts/strip-ytdlp.sh                       # operates on Vendor/yt-dlp
#   Scripts/strip-ytdlp.sh path/to/yt-dlp-dir    # explicit path
#
# Run this after pulling a fresh PyInstaller yt-dlp release into Vendor/.

set -euo pipefail

YTDLP_DIR="${1:-$(dirname "$0")/../Vendor/yt-dlp}"
YTDLP_DIR="$(cd "$YTDLP_DIR" && pwd)"

if [ ! -d "$YTDLP_DIR/_internal" ]; then
    echo "ERROR: $YTDLP_DIR doesn't look like a PyInstaller yt-dlp dist" >&2
    exit 1
fi

echo "Stripping yt-dlp at: $YTDLP_DIR"
echo "Before: $(du -sh "$YTDLP_DIR" | awk '{print $1}')"

# 1. Thin everything universal to arm64.
#    Walks every Mach-O file (main binary, dylibs, .so extension modules,
#    Python.framework's Python binary) and replaces it with the arm64 slice
#    if a universal binary is present. `lipo` exits non-zero on single-arch
#    files, so we suppress errors and keep going.
thin_arm64() {
    local f="$1"
    file "$f" 2>/dev/null | grep -q "2 architectures" || return 0
    local tmp="${f}.arm64.tmp"
    if lipo -thin arm64 "$f" -output "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
    else
        rm -f "$tmp"
    fi
}

# Main binary
thin_arm64 "$YTDLP_DIR/yt-dlp_macos"

# Every dylib + .so in _internal (recursive)
while IFS= read -r -d '' f; do
    thin_arm64 "$f"
done < <(find "$YTDLP_DIR/_internal" \( -name "*.dylib" -o -name "*.so" \) -print0)

# Python.framework's main binary (the one named just "Python", not the symlink)
while IFS= read -r -d '' f; do
    # Skip symlinks; lipo on a symlink rewrites the target which is fine,
    # but skipping them avoids double-processing.
    [ -L "$f" ] && continue
    thin_arm64 "$f"
done < <(find "$YTDLP_DIR/_internal/Python.framework" -type f -print0 2>/dev/null)

# 2. Remove curl_cffi (browser-impersonation HTTP client) + its companion
#    dylib + dist-info. yt-dlp's networking layer falls back to urllib when
#    curl_cffi isn't importable. Verified format-listing parity on YouTube
#    against `https://www.youtube.com/watch?v=jNQXAC9IVRw` (11 formats before
#    and after).
rm -rf "$YTDLP_DIR/_internal/curl_cffi"
rm -rf "$YTDLP_DIR/_internal/curl_cffi-0.13.0.dist-info"
rm -f  "$YTDLP_DIR/_internal/libcurl-impersonate.4.dylib"

echo "After:  $(du -sh "$YTDLP_DIR" | awk '{print $1}')"
echo
echo "Quick sanity check (asks YouTube for the first uploaded video):"
if [ -x "$YTDLP_DIR/yt-dlp_macos" ]; then
    "$YTDLP_DIR/yt-dlp_macos" --simulate --get-title \
        "https://www.youtube.com/watch?v=jNQXAC9IVRw" 2>/dev/null || \
        echo "  (offline or YouTube unreachable — skip)"
fi
