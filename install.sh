#!/bin/sh
# ---------------------------------------------------------------------------
# Install nb2cleanpdf into a bin directory (default: ~/.local/bin).
#
#   ./install.sh [options]                  from a clone of the repository
#   curl -fsSL https://raw.githubusercontent.com/Yuxin-Ren-SZ/nb2cleanpdf/main/install.sh | sh
#   curl -fsSL …/install.sh | sh -s -- --prefix /usr/local
#   curl -fsSL …/install.sh | sh -s -- --version 0.2.0
#
# Options:
#   --bin-dir DIR   install into DIR (default: ~/.local/bin)
#   --prefix DIR    same as --bin-dir DIR/bin
#   --version VER   install release VER (e.g. 0.2.0) instead of the main branch;
#                   always downloads, even from a clone
#   --link          symlink to the clone instead of copying (updates with git pull)
#   --force         overwrite DIR/nb2cleanpdf even if it isn't nb2cleanpdf
#   --uninstall     remove DIR/nb2cleanpdf
#   -h, --help      show this help
#
# Environment: NB2CLEANPDF_VERSION = --version; NB2CLEANPDF_URL overrides where
# the script is downloaded from when install.sh runs outside a clone
# (default: the main branch on GitHub).
# ---------------------------------------------------------------------------
set -eu

NAME=nb2cleanpdf
RAW=https://raw.githubusercontent.com/Yuxin-Ren-SZ/nb2cleanpdf
MARKER="# $NAME — "          # first comment line of the real script identifies it

if [ -t 1 ]; then R=$(printf '\033[31m') G=$(printf '\033[32m') Y=$(printf '\033[33m') D=$(printf '\033[2m') N=$(printf '\033[0m')
else R='' G='' Y='' D='' N=''; fi
info() { printf '%s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
usage() {
  if [ -f "$0" ]; then sed -n '3,22p' "$0" | cut -c3-
  else info "options: --bin-dir DIR | --prefix DIR | --version VER | --link | --force | --uninstall"; fi
}

BIN_DIR=$HOME/.local/bin LINK=0 FORCE=0 UNINSTALL=0 VERSION=${NB2CLEANPDF_VERSION:-}
while [ $# -gt 0 ]; do
  case $1 in
    --bin-dir)   [ $# -ge 2 ] || die "--bin-dir needs a directory"; BIN_DIR=$2; shift 2 ;;
    --bin-dir=*) BIN_DIR=${1#*=}; shift ;;
    --prefix)    [ $# -ge 2 ] || die "--prefix needs a directory"; BIN_DIR=$2/bin; shift 2 ;;
    --prefix=*)  BIN_DIR=${1#*=}/bin; shift ;;
    --version)   { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--version needs a version, e.g. 0.2.0"; VERSION=$2; shift 2 ;;
    --version=*) VERSION=${1#*=}; shift ;;
    --link)      LINK=1; shift ;;
    --force)     FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown option '$1' (see --help)" ;;
  esac
done
case $BIN_DIR in /*) ;; *) BIN_DIR=$PWD/$BIN_DIR ;; esac
if [ -n "$VERSION" ]; then
  VERSION=${VERSION#v}
  case $VERSION in
    *[!0-9.]*|.*|*.|*..*|'') die "--version must look like 0.2.0 (got '$VERSION')" ;;
  esac
  [ -z "${NB2CLEANPDF_URL:-}" ] || die "--version and NB2CLEANPDF_URL can't be combined"
  [ $LINK -eq 0 ] || die "--version downloads a release; it can't be combined with --link"
  URL=$RAW/v$VERSION/$NAME
else
  URL=${NB2CLEANPDF_URL:-$RAW/main/$NAME}
fi
TARGET=$BIN_DIR/$NAME

is_ours() {   # $1 = file: an nb2cleanpdf script (or a symlink to one)?
  [ -f "$1" ] && sed -n '3p' "$1" 2>/dev/null | grep -q "^$MARKER"
}

# ---------- uninstall ------------------------------------------------------------
if [ $UNINSTALL -eq 1 ]; then
  if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then info "nothing to remove: $TARGET does not exist"; exit 0; fi
  is_ours "$TARGET" || [ $FORCE -eq 1 ] || die "$TARGET is not $NAME — not removing it (use --force to remove anyway)"
  rm -f "$TARGET"
  info "${G}✓${N} removed $TARGET"
  info "${D}run records (.nb2cleanpdf/) and PDFs in your projects are left alone; 'nb2cleanpdf clean' removes records${N}"
  exit 0
fi

# ---------- find the script: the clone next to install.sh, or download it ----------
SRC='' TMPF=''
if [ -z "$VERSION" ]; then
  case $0 in
    */install.sh|install.sh) HERE=$(cd "$(dirname "$0")" && pwd -P); [ -f "$HERE/$NAME" ] && SRC=$HERE/$NAME ;;
  esac
fi
if [ -z "$SRC" ]; then
  [ $LINK -eq 0 ] || die "--link needs a clone of the repository (run ./install.sh from it)"
  command -v curl >/dev/null 2>&1 || die "curl is needed to download $NAME"
  TMPF=$(mktemp "${TMPDIR:-/tmp}/$NAME.XXXXXX")
  trap 'rm -f "$TMPF"' EXIT
  info "downloading $URL"
  if ! curl -fsSL "$URL" -o "$TMPF"; then
    [ -z "$VERSION" ] || die "download failed: $URL — is v$VERSION a release? See https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/releases"
    die "download failed: $URL"
  fi
  SRC=$TMPF
fi
is_ours "$SRC" || die "$SRC does not look like $NAME — refusing to install it"

# ---------- install ---------------------------------------------------------------
if { [ -e "$TARGET" ] || [ -L "$TARGET" ]; } && ! is_ours "$TARGET" && [ $FORCE -eq 0 ]; then
  die "$TARGET exists and is not $NAME — not overwriting it (use --force, or another --bin-dir)"
fi
mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
if [ $LINK -eq 1 ]; then
  ln -sfn "$SRC" "$TARGET"
  how="symlink → $SRC"
else
  # copy to a temp name first, then rename: a running nb2cleanpdf keeps its old file
  if ! { cp "$SRC" "$TARGET.tmp.$$" && chmod 755 "$TARGET.tmp.$$" && mv -f "$TARGET.tmp.$$" "$TARGET"; }; then
    rm -f "$TARGET.tmp.$$"; die "cannot write $TARGET"
  fi
  how="copy"
fi
ver=$(sed -n 's/^VERSION=\([0-9.]*\).*/\1/p' "$SRC" | head -n 1)
info "${G}✓${N} installed $TARGET ${D}($how${ver:+, version $ver})${N}"

# ---------- after-install checks (advice only) -----------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH. Add it, e.g. for zsh:"
     printf "         echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc && exec zsh\n" "$BIN_DIR" >&2 ;;
esac
command -v zsh >/dev/null 2>&1 || warn "zsh not found — $NAME is a zsh script (macOS ships it; on Linux: apt install zsh)"
command -v uv  >/dev/null 2>&1 || warn "uv not found — install it: brew install uv   (or see https://docs.astral.sh/uv/)"
old=$BIN_DIR/nbrerun          # the previous name of the tool
if [ -e "$old" ]; then
  warn "an old version is still installed as $old (the previous name) — remove it with: rm '$old'"
fi
info "run '${NAME} -h' for usage"
