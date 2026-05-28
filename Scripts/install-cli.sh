#!/usr/bin/env bash
#
# install-cli.sh — symlinks `awesomeplayer` into /usr/local/bin (or another
# prefix on PATH). After install, you can run `awesomeplayer ~/Movies/foo.mkv`
# from anywhere.
#
# Usage:
#   ./Scripts/install-cli.sh                 # installs to /usr/local/bin (default)
#   ./Scripts/install-cli.sh --prefix ~/bin  # installs to a custom prefix
#   ./Scripts/install-cli.sh --uninstall     # removes the symlink
#
# Reinstall-safe: removes any existing symlink first, then re-creates.

set -e

PREFIX="/usr/local/bin"
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

LINK="$PREFIX/awesomeplayer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/awesomeplayer"

if [ "$UNINSTALL" = "1" ]; then
    if [ -L "$LINK" ]; then
        rm "$LINK" && echo "Removed $LINK"
    else
        echo "Not installed at $LINK — nothing to do."
    fi
    exit 0
fi

if [ ! -f "$SOURCE" ]; then
    echo "Source not found: $SOURCE"
    exit 1
fi

chmod +x "$SOURCE"

if [ ! -d "$PREFIX" ]; then
    echo "Prefix $PREFIX does not exist. Create it first or pass --prefix."
    exit 1
fi

# /usr/local/bin needs sudo on default macOS install; ~/bin doesn't.
if [ -w "$PREFIX" ]; then
    ln -sf "$SOURCE" "$LINK"
else
    sudo ln -sf "$SOURCE" "$LINK"
fi

echo "Installed: $LINK -> $SOURCE"
echo "Test: awesomeplayer ~/Movies/<somefile>"
