#!/bin/bash
# Installs the latest BlackSharkBattery release from GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/matej-basic/blackshark-battery/main/install.sh | bash
#
# Options:  --dry-run         print the steps and URLs, download and change nothing
#                             (through a pipe: ... | bash -s -- --dry-run)
# Environment:
#   BSB_VERSION=v0.1.0        install this release tag instead of the latest
#   INSTALL_DIR=/some/dir     install here instead of /Applications
#
# Needs only tools that ship with macOS: curl, ditto, xattr, shasum.
#
# Everything happens inside main(), which is called on the last line. When the
# script is piped into bash and the download stops early, bash has only read
# variable assignments and function definitions, so nothing runs.
set -euo pipefail

REPO="matej-basic/blackshark-battery"
NAME="BlackSharkBattery"
BUNDLE_ID="com.matejbasic.BlackSharkBattery"
TMP=""

cleanup() {
    if [ -n "$TMP" ]; then
        rm -rf "$TMP"
    fi
}

main() {
    DRY_RUN=0
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            -h | --help)
                echo "Usage: install.sh [--dry-run]    (BSB_VERSION=v0.1.0, INSTALL_DIR=/some/dir)"
                exit 0
                ;;
            *)
                echo "Unknown option: $arg (try --dry-run)" >&2
                exit 2
                ;;
        esac
    done

    if [ "$(uname -s)" != "Darwin" ]; then
        echo "This installer is for macOS only." >&2
        exit 1
    fi

    if [ -n "${BSB_VERSION:-}" ]; then
        BASE="https://github.com/$REPO/releases/download/$BSB_VERSION"
    else
        BASE="https://github.com/$REPO/releases/latest/download"
    fi

    # Choose the install directory. /Applications is the default; if it is not
    # writable for this user, fall back to ~/Applications. An explicit INSTALL_DIR
    # is never replaced by a fallback.
    if [ -n "${INSTALL_DIR:-}" ]; then
        DEST_DIR="$INSTALL_DIR"
    elif [ -w /Applications ]; then
        DEST_DIR="/Applications"
    else
        DEST_DIR="$HOME/Applications"
        echo "/Applications is not writable for this user, using $DEST_DIR instead."
    fi
    DEST="$DEST_DIR/$NAME.app"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry run: nothing will be downloaded or changed."
        echo
        echo "1. Check that this is macOS (it is)"
        echo "2. Download $BASE/SHA256SUMS"
        echo "   to learn the zip name and its sha256"
        echo "3. Download $BASE/<zip named in SHA256SUMS>"
        echo "   (into a temporary directory)"
        echo "4. Verify the zip with: shasum -a 256 -c SHA256SUMS"
        echo "5. Extract with: ditto -x -k"
        echo "6. Remove the quarantine flag: xattr -dr com.apple.quarantine $NAME.app"
        echo "7. Quit a running copy: pkill -x $NAME"
        echo "8. Replace $DEST"
        echo "9. Start it: open $DEST"
        exit 0
    fi

    TMP="$(mktemp -d)"
    trap cleanup EXIT

    # --proto =https also applies to redirects, so a redirect cannot drop to http.
    echo "Downloading $BASE/SHA256SUMS"
    curl -fsSL --proto '=https' --retry 3 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS"

    # The file has one line: "<sha256>  <zip name>" (a leading * on the name marks
    # binary mode and is dropped).
    SUM="$(awk 'NF >= 2 { print $1; exit }' "$TMP/SHA256SUMS")"
    ASSET="$(awk 'NF >= 2 { sub(/^\*/, "", $2); print $2; exit }' "$TMP/SHA256SUMS")"
    # shasum -c picks the algorithm from the length of the hash, so insist on a
    # sha256 here; a shorter (sha1) hash would otherwise be accepted.
    if ! [[ "$SUM" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Unexpected sha256 in SHA256SUMS: '$SUM'" >&2
        exit 1
    fi
    case "$ASSET" in
        "" | */*)
            echo "Unexpected asset name in SHA256SUMS: '$ASSET'" >&2
            exit 1
            ;;
        "$NAME"-*.zip) ;;
        *)
            echo "Unexpected asset name in SHA256SUMS: '$ASSET'" >&2
            exit 1
            ;;
    esac

    echo "Downloading $BASE/$ASSET"
    curl -fL --proto '=https' --progress-bar --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET"

    echo "Verifying sha256"
    (cd "$TMP" && shasum -a 256 -c SHA256SUMS)

    echo "Extracting"
    mkdir "$TMP/extract"
    ditto -x -k "$TMP/$ASSET" "$TMP/extract"
    if [ ! -d "$TMP/extract/$NAME.app" ]; then
        echo "$NAME.app not found in $ASSET" >&2
        exit 1
    fi
    xattr -dr com.apple.quarantine "$TMP/extract/$NAME.app"

    echo "Installing to $DEST"
    pkill -x "$NAME" 2>/dev/null || true
    mkdir -p "$DEST_DIR"
    rm -rf "${DEST:?}"
    ditto "$TMP/extract/$NAME.app" "$DEST"
    # ditto copies extended attributes; make sure none of them is the quarantine flag.
    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

    open "$DEST"

    echo
    echo "Installed $ASSET to $DEST and started it."
    echo "Look for the headphones icon in the menu bar."
    echo
    echo "To uninstall:"
    echo "  pkill -x $NAME; rm -rf \"$DEST\""
    echo "  defaults delete $BUNDLE_ID"
}

# The braces make every shorter version of this line a syntax error, so a cut
# after "main" cannot run main without its arguments (and drop --dry-run).
{ main "$@"; }
