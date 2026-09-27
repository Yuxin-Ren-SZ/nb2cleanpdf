#!/usr/bin/env zsh
# Re-record docs/images/{demo.gif,picker.png,run.png,summary.png} with vhs.
# Usage: docs/demo/record.zsh          (needs vhs, fzf, uv; run from anywhere)
emulate -R zsh
setopt err_exit pipe_fail
REPO=${0:A:h:h:h}
DEMO_DIR=$(mktemp -d "${${TMPDIR:-/tmp}%/}/nb2cleanpdf-demo.XXXXXX")/my-project
trap 'rm -rf -- ${DEMO_DIR:h}' EXIT
$REPO/docs/demo/make-demo.zsh $DEMO_DIR
# warm-up run, so kernel start and PDF engine downloads don't end up in the recording
( cd $DEMO_DIR && $REPO/nb2cleanpdf -y -e draft >/dev/null 2>&1 ) || true
cd $REPO
export REPO DEMO_DIR
vhs docs/demo/demo.tape
