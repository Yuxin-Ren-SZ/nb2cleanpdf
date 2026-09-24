#!/usr/bin/env zsh
# ---------------------------------------------------------------------------
# Functional tests for nbrerun. Builds a scratch uv project with a notebook
# fixture under tests/.work/<engine>/ and drives the real script against it.
#
#   tests/run-tests.zsh [--engine ENGINE]
#
# ENGINE is passed to `nbrerun --engine` (auto, chrome, webpdf, latex), or
# `none` to skip PDF export entirely. Missing PDF dependencies are installed
# with --install-deps. The work dir is kept afterwards (logs, PDFs) and wiped
# at the start of the next run.
# ---------------------------------------------------------------------------
emulate -R zsh
setopt extended_glob pipe_fail

ROOT=${0:A:h:h}
NBRERUN=$ROOT/nbrerun
ENGINE=auto

while (( $# )); do
  case $1 in
    --engine)   ENGINE=$2; shift 2 ;;
    --engine=*) ENGINE=${1#*=}; shift ;;
    -h|--help)  sed -n '3,12p' $0 | cut -c3-; exit 0 ;;
    *)          print -u2 "unknown argument '$1'"; exit 2 ;;
  esac
done

WORK=$ROOT/tests/.work/$ENGINE
P=$WORK/proj

# ---------- helpers -----------------------------------------------------------
integer PASS=0 FAIL=0
typeset -a FAILED
OUT= RC=0

section() { print -r -- $'\n'"== $*" }
die()     { print -ru2 -- "setup failed: $*"; exit 2 }

# run nbrerun without a TTY; output -> $OUT, status -> $RC
nbr() { OUT=$("$NBRERUN" "$@" </dev/null 2>&1); RC=$? }

# check DESCRIPTION EXPR — EXPR is eval'ed; on failure the last output is shown
check() {
  if eval "$2"; then
    (( PASS++ )); print -r -- "  ok    $1"
  else
    (( FAIL++ )); FAILED+=("$1"); print -r -- "  FAIL  $1   [$2]  rc=$RC"
    print -r -- "$OUT" | tail -n 30 | sed 's/^/        | /'
  fi
}
has()    { [[ $OUT == *"$1"* ]] }
listed() { print -r -- ${#${(M)${(f)OUT}:#  *.ipynb}} }     # notebooks listed by -n

py() { $P/.venv/bin/python "$@" }
outputs() {   # all stream/text outputs of a notebook
  py -c 'import json,sys
nb = json.load(open(sys.argv[1], encoding="utf-8"))
for c in nb["cells"]:
    for o in c.get("outputs", []):
        t = o.get("text", "")
        print("".join(t) if isinstance(t, list) else t, end="")' "$1"
}
kernel_name() { py -c 'import json,sys; print(json.load(open(sys.argv[1]))["metadata"]["kernelspec"]["name"])' "$1" }
pdf_text()   { py -c 'import sys,pypdf; print("".join(p.extract_text() or "" for p in pypdf.PdfReader(sys.argv[1]).pages))' "$1" 2>/dev/null }
pdf_images() { py -c 'import sys,pypdf; print(sum(len(p.images) for p in pypdf.PdfReader(sys.argv[1]).pages))' "$1" 2>/dev/null }
is_pdf()     { [[ -s $1 && $(head -c 4 -- "$1") == %PDF ]] }
count()      { print -r -- $# }                             # count PATTERN(N)
has_line()   { (( ${${(f)"$(outputs $1)"}[(Ie)$2]} )) }   # notebook $1 printed exactly line $2

# ---------- fixture -------------------------------------------------------------
section "setup ($ENGINE)"
rm -rf -- $WORK && mkdir -p $P || die "cannot create $P"
cd $P || die "cd $P"
uv init --bare -q                                        || die "uv init"
uv add --dev -q jupyter numpy matplotlib pypdf           || die "uv add"
uv run -q python $ROOT/tests/make_fixture.py .           || die "fixture"
print -r -- "  project: $P"

typeset -a PDFARGS NB_EXCL
if [[ $ENGINE == none ]]; then
  PDFARGS=(--no-pdf)
else
  PDFARGS=(--engine $ENGINE --install-deps)
fi
[[ $ENGINE == latex ]] && NB_EXCL=(-e unicode)            # nbconvert's LaTeX template can't do CJK

# ---------- discovery and filters ----------------------------------------------
section "discovery and filters"
nbr -n;                          check "dry-run finds all 6 notebooks"      '(( RC == 0 )) && (( $(listed) == 6 ))'
nbr -n -i eda;                   check "plain word = substring of path"     '(( $(listed) == 1 )) && has "analysis/sub/eda.ipynb"'
nbr -n -e scratch;               check "exclude by plain word"              '(( $(listed) == 4 ))'
nbr -n -i 'analysis/*';          check "glob with / crosses dirs"           '(( $(listed) == 2 ))'
nbr -n -i 'fig*';                check "glob without / = file name"         '(( $(listed) == 1 ))'
nbr -n -i '(#i)*EDA*';           check "(#i) is case-insensitive"           '(( $(listed) == 1 ))'
nbr -n -i eda -i intro;          check "includes are OR-ed"                 '(( $(listed) == 2 ))'
nbr -n -i 'analysis/*' -e eda;   check "exclude applied after include"      '(( $(listed) == 1 ))'
nbr -n -i foo bar;               check "stray argument suggests quoting"    '(( RC == 1 )) && has "Quote it"'
nbr -n --timeout abc;            check "bad --timeout rejected"             '(( RC == 1 ))'
nbr -n --engine nope;            check "bad --engine rejected"              '(( RC == 1 ))'
nbr -n --keep 1;                 check "--keep outside clean rejected"      '(( RC == 1 ))'
nbr --no-exec --no-pdf;          check "--no-exec --no-pdf rejected"        '(( RC == 1 ))'

# ---------- venv validation ------------------------------------------------------
section "venv validation"
V=$WORK/venvs
mkdir -p $V/none $V/notuv/.venv/bin $V/empty
cp -- $P/intro.ipynb $V/none/ && cp -- $P/intro.ipynb $V/notuv/ && cp -- $P/intro.ipynb $V/empty/
print 'home = /usr/bin' >$V/notuv/.venv/pyvenv.cfg
(cd $V/empty && uv venv -q) || die "uv venv"

cd $V/none;  nbr -y;  check "missing venv is an error"          '(( RC == 1 )) && has "no virtualenv found"'
cd $V/notuv; nbr -y;  check "non-uv venv is an error"           '(( RC == 1 )) && has "not created by uv"'
cd $V/empty; nbr -y --no-pdf
check "missing deps listed with install command" '(( RC == 1 )) && has "uv pip install --python .venv jupyter" && has "no TTY"'
cd $P

# ---------- successful run ---------------------------------------------------------
section "clean re-run + PDF export"
nbr -y -e scratch $NB_EXCL $PDFARGS
check "run succeeds"                         '(( RC == 0 )) && has "All done."'
check "outputs were produced"                '[[ $(outputs intro.ipynb) == *hello-from-intro* ]]'
check "cwd = notebook directory"             'has_line intro.ipynb "CWD=$P" && [[ -f analysis/local.txt ]]'
check "kernel runs the venv interpreter"     'has_line intro.ipynb "EXE=$P/.venv/bin/python"'
check "original kernelspec restored"         '[[ $(kernel_name intro.ipynb) == python3 ]]'
check "backups written"                      '(( $(count .nbrerun/*/backup/intro.ipynb(N)) == 1 && $(count .nbrerun/*/backup/analysis/fig\ 1.v2.ipynb(N)) == 1 ))'
check "no temp files left"                   '(( $(count **/.*.nbrerun-tmp(N)) == 0 ))'

if [[ $ENGINE != none ]]; then
  check "PDFs next to notebooks"             'is_pdf intro.pdf && is_pdf "analysis/fig 1.v2.pdf" && is_pdf analysis/sub/eda.pdf'
  check "PDF has cell output text"           '[[ $(pdf_text intro.pdf) == *hello-from-intro* ]]'
  check "PDF embeds the plot"                '(( $(pdf_images "analysis/fig 1.v2.pdf") >= 1 ))'
  [[ $ENGINE != latex ]] && \
  check "PDF shows CJK text"                 '[[ $(pdf_text unicode/cjk.pdf) == *中* ]]'

  nbr -y --no-exec -i eda -o out $PDFARGS
  check "-o mirrors the folder layout"       '(( RC == 0 )) && is_pdf out/analysis/sub/eda.pdf'
fi

# ---------- failures ------------------------------------------------------------------
section "failure handling"
cp -- scratch/broken.ipynb $WORK/broken.orig && cp -- scratch/slow.ipynb $WORK/slow.orig
nbr -y -t 3 -i scratch $PDFARGS
check "exit status 1"                        '(( RC == 1 )) && has "2 notebook(s) had errors"'
check "cell error summarised"                'has "execution failed" && has "ZeroDivisionError"'
check "timeout reported"                     'has "cell timed out"'
check "originals untouched on failure"       'cmp -s scratch/broken.ipynb $WORK/broken.orig && cmp -s scratch/slow.ipynb $WORK/slow.orig'
check "partial copies saved"                 '(( $(count .nbrerun/*/failed/*.ipynb(N)) >= 2 ))'
[[ $ENGINE != none ]] && \
check "PDF skipped after failed execution"   'has "PDF skipped"'

nbr -y --allow-errors -i broken --no-pdf
check "--allow-errors runs to the end"       '(( RC == 0 )) && [[ $(outputs scratch/broken.ipynb) == *never-reached* ]]'

# ---------- clean ------------------------------------------------------------------------
section "clean"
mkdir -p long
py - <<'EOF'
import nbformat as nbf
nb = nbf.v4.new_notebook()
nb.metadata["kernelspec"] = {"name": "python3", "display_name": "Python 3", "language": "python"}
nb.cells = [nbf.v4.new_code_cell("import time; time.sleep(120)")]
nbf.write(nb, "long/long.ipynb")
EOF
"$NBRERUN" -y -i long --no-pdf </dev/null >$WORK/long.out 2>&1 &
LONG=$!
for i in {1..60}; do            # wait until the exec helper is running
  command ps -U $UID -o command= | command grep -q "nbrerun\.$LONG\..*exec\.py" && break
  sleep 0.5
done

nbr clean -n
check "live run is detected and kept"        'has "in progress" && has "live"'
kill -9 $LONG 2>/dev/null; wait $LONG 2>/dev/null; sleep 1
nbr clean -n
check "orphans found after kill -9"          'has "Orphaned processes" && has "Orphaned temp dirs"'
nbr clean -y --keep 1
check "clean removes orphans"                '(( RC == 0 )) && has "Clean."'
check "no orphaned processes remain"         '! command ps -U $UID -o command= | command grep -q "nbrerun\.$LONG\."'
check "orphaned temp dir removed"            '(( $(count ${${TMPDIR:-/tmp}%/}/nbrerun.$LONG.*(N)) == 0 ))'
check "--keep 1 kept one run record"         '(( $(count .nbrerun/<->-<->(N/)) == 1 ))'

if [[ $ENGINE != none ]]; then
  nbr clean -n --pdfs -e scratch
  check "clean --pdfs lists exported PDFs"   'has "Exported PDFs" && has "intro.pdf"'
  nbr clean -y --pdfs
  check "clean --pdfs removes them"          '(( RC == 0 )) && [[ ! -e intro.pdf ]]'
fi
nbr clean -y
nbr clean -n
check "nothing left to clean"                'has "nothing to clean"'

# ---------- summary -------------------------------------------------------------------------
print
if (( FAIL )); then
  print -r -- "$FAIL failed, $PASS passed ($ENGINE):"
  print -rl -- "  - "${^FAILED}
  exit 1
fi
print -r -- "all $PASS checks passed ($ENGINE)"
