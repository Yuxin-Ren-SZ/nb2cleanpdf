#!/usr/bin/env zsh
# ---------------------------------------------------------------------------
# Functional tests for nb2cleanpdf. Builds a scratch uv project with a notebook
# fixture under tests/.work/<engine>/ and drives the real script against it.
#
#   tests/run-tests.zsh [--engine ENGINE]
#
# ENGINE is passed to `nb2cleanpdf --engine` (auto, chrome, chrome-cli, webpdf, latex), or
# `none` to skip PDF export entirely. Missing PDF dependencies are installed
# with --install-deps. The work dir is kept afterwards (logs, PDFs) and wiped
# at the start of the next run.
# ---------------------------------------------------------------------------
emulate -R zsh
setopt extended_glob pipe_fail

ROOT=${0:A:h:h}
NB2CLEANPDF=$ROOT/nb2cleanpdf
ENGINE=auto

while (( $# )); do
  case $1 in
    --engine)   ENGINE=$2; shift 2 ;;
    --engine=*) ENGINE=${1#*=}; shift ;;
    -h|--help)  sed -n '3,12p' $0 | cut -c3-; exit 0 ;;
    *)          print -u2 "unknown argument '$1'"; exit 2 ;;
  esac
done
# $ENGINE becomes part of a path that is rm -rf'd below
[[ $ENGINE == (auto|chrome|chrome-cli|webpdf|latex|none) ]] ||
  { print -u2 "invalid --engine '$ENGINE' (auto|chrome|chrome-cli|webpdf|latex|none)"; exit 2 }

WORK=$ROOT/tests/.work/$ENGINE
P=$WORK/proj

# ---------- helpers -----------------------------------------------------------
integer PASS=0 FAIL=0
typeset -a FAILED
OUT= RC=0

section() { print -r -- $'\n'"== $*" }
die()     { print -ru2 -- "setup failed: $*"; exit 2 }

# run nb2cleanpdf without a TTY; output -> $OUT, status -> $RC
nbr() { OUT=$("$NB2CLEANPDF" "$@" </dev/null 2>&1); RC=$? }
# same, but on a pseudo-terminal (BSD and util-linux `script` differ)
nbr_tty() {
  if [[ $OSTYPE == darwin* ]]; then
    OUT=$(script -q /dev/null "$NB2CLEANPDF" "$@" </dev/null 2>&1)
  else
    OUT=$(script -qec "${(q)NB2CLEANPDF} ${(j: :)${(q)@}}" /dev/null </dev/null 2>&1)
  fi
  RC=$?
}

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

# ---------- install script -------------------------------------------------------
section "install script"
INST=$ROOT/install.sh
I=$WORK/inst
inst() { OUT=$(sh "$@" </dev/null 2>&1); RC=$? }
inst $INST --bin-dir $I/bin
check "installs a copy"                      '(( RC == 0 )) && [[ -f $I/bin/nb2cleanpdf && ! -L $I/bin/nb2cleanpdf && -x $I/bin/nb2cleanpdf ]] && cmp -s $I/bin/nb2cleanpdf $NB2CLEANPDF'
check "warns when bin dir is not on PATH"    'has "is not on your PATH"'
OUT=$($I/bin/nb2cleanpdf -h 2>&1); RC=$?
check "installed command runs"               '(( RC == 0 )) && has "Usage:"'
inst $INST --bin-dir $I/bin
check "re-install (upgrade) works"           '(( RC == 0 ))'
OUT=$(PATH=$I/bin:$PATH sh $INST --bin-dir $I/bin </dev/null 2>&1); RC=$?
check "no PATH warning when on PATH"         '(( RC == 0 )) && ! has "not on your PATH"'
inst $INST --prefix $I/pfx --link
check "--prefix + --link symlinks the clone" '(( RC == 0 )) && [[ -L $I/pfx/bin/nb2cleanpdf && $I/pfx/bin/nb2cleanpdf -ef $NB2CLEANPDF ]]'
inst $INST --bin-dir $I/pfx/bin
check "copy replaces an earlier symlink"     '(( RC == 0 )) && [[ ! -L $I/pfx/bin/nb2cleanpdf ]]'
mkdir -p $I/foreign && print 'echo not ours' >$I/foreign/nb2cleanpdf
inst $INST --bin-dir $I/foreign
check "refuses to overwrite a foreign file"  '(( RC == 1 )) && [[ $(<$I/foreign/nb2cleanpdf) == "echo not ours" ]]'
inst $INST --bin-dir $I/foreign --uninstall
check "refuses to remove a foreign file"     '(( RC == 1 )) && [[ -f $I/foreign/nb2cleanpdf ]]'
inst $INST --bin-dir $I/foreign --force
check "--force overwrites"                   '(( RC == 0 )) && cmp -s $I/foreign/nb2cleanpdf $NB2CLEANPDF'
print 'x' >$I/bin/nbrerun
inst $INST --bin-dir $I/bin
check "points out the old nbrerun"           'has "old version is still installed"'
inst $INST --bin-dir $I/bin --uninstall
check "--uninstall removes it"               '(( RC == 0 )) && [[ ! -e $I/bin/nb2cleanpdf ]]'
inst $INST --bin-dir $I/bin --uninstall
check "--uninstall when absent is fine"      '(( RC == 0 )) && has "nothing to remove"'
# `curl … | sh` mode: install.sh on its own, the script fetched from a URL
OUT=$(NB2CLEANPDF_URL=file://$NB2CLEANPDF sh -s -- --bin-dir $I/remote <$INST 2>&1); RC=$?
check "piped install downloads the script"   '(( RC == 0 )) && has "downloading" && cmp -s $I/remote/nb2cleanpdf $NB2CLEANPDF'
OUT=$(NB2CLEANPDF_URL=file://$INST sh -s -- --bin-dir $I/remote2 <$INST 2>&1); RC=$?
check "rejects a download that isn't it"     '(( RC == 1 )) && [[ ! -e $I/remote2/nb2cleanpdf ]]'
inst $INST --bin-dir $I/v --version 1.x
check "--version rejects a malformed version" '(( RC == 1 )) && has "must look like" && [[ ! -e $I/v ]]'
inst $INST --bin-dir $I/v --version 0.1.0 --link
check "--version with --link rejected"       '(( RC == 1 )) && [[ ! -e $I/v ]]'
OUT=$(NB2CLEANPDF_URL=file://$NB2CLEANPDF sh $INST --bin-dir $I/v --version 0.1.0 </dev/null 2>&1); RC=$?
check "--version with NB2CLEANPDF_URL rejected" '(( RC == 1 )) && [[ ! -e $I/v ]]'
inst $INST --bin-dir $I/v --version v0.1.0     # needs network (GitHub)
check "--version downloads the release tag"  '(( RC == 0 )) && has "/v0.1.0/nb2cleanpdf" && [[ -x $I/v/nb2cleanpdf ]]'
inst $INST --bin-dir $I/v --version 0.0.0
check "--version of a missing release fails" '(( RC == 1 )) && has "a release?"'
inst $INST --bin-dir $I/v
check "reports the installed version"        "(( RC == 0 )) && has \"version \$(\$NB2CLEANPDF -V | cut -d' ' -f2)\""
OUT=$($NB2CLEANPDF --version 2>&1); RC=$?
check "--version prints the version"         '(( RC == 0 )) && [[ $OUT == "nb2cleanpdf "<->.<->.<-> ]]'

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
check "backups written"                      '(( $(count .nb2cleanpdf/*/backup/intro.ipynb(N)) == 1 && $(count .nb2cleanpdf/*/backup/analysis/fig\ 1.v2.ipynb(N)) == 1 ))'
check "no temp files left"                   '(( $(count **/.*.nb2cleanpdf-tmp(N)) == 0 ))'

if [[ $ENGINE != none ]]; then
  check "PDFs go to PDF/, mirroring folders" 'is_pdf PDF/intro.pdf && is_pdf "PDF/analysis/fig 1.v2.pdf" && is_pdf PDF/analysis/sub/eda.pdf'
  check "nothing written next to notebooks"  '[[ ! -e intro.pdf && ! -e analysis/sub/eda.pdf ]]'
  check "PDF has cell output text"           '[[ $(pdf_text PDF/intro.pdf) == *hello-from-intro* ]]'
  check "PDF embeds the plot"                '(( $(pdf_images "PDF/analysis/fig 1.v2.pdf") >= 1 ))'
  [[ $ENGINE != latex ]] && \
  check "PDF shows CJK text"                 '[[ $(pdf_text PDF/unicode/cjk.pdf) == *中* ]]'
  nbr -n
  check "PDF/ is not searched for notebooks" '(( $(listed) == 6 ))'
  [[ $ENGINE == (auto|chrome) ]] && \
  check "playwright kept out of the venv"    '! py -c "import playwright" 2>/dev/null && ! command grep -q playwright pyproject.toml uv.lock'

  nbr -y --no-exec -i eda -o out $PDFARGS
  check "-o mirrors the folder layout"       '(( RC == 0 )) && is_pdf out/analysis/sub/eda.pdf'
  nbr -y --no-exec -i eda -o . $PDFARGS
  check "-o . puts PDFs next to notebooks"   '(( RC == 0 )) && is_pdf analysis/sub/eda.pdf'
  rm -f analysis/sub/eda.pdf
fi

# ---------- running from another location --------------------------------------------
section "running from another location"
mkdir -p $WORK/bin
cp -- $NB2CLEANPDF $WORK/bin/nb2cleanpdf && ln -sf $WORK/bin/nb2cleanpdf $WORK/bin/nbx
typeset -a RUNARGS=(-y -i intro $PDFARGS)

OUT=$(../bin/nb2cleanpdf -n </dev/null 2>&1); RC=$?
check "script called by a relative path"     '(( RC == 0 )) && (( $(listed) == 6 ))'
OUT=$(PATH=$WORK/bin:$PATH nb2cleanpdf -n </dev/null 2>&1); RC=$?
check "script installed on PATH"             '(( RC == 0 )) && (( $(listed) == 6 ))'
OUT=$($WORK/bin/nbx $RUNARGS </dev/null 2>&1); RC=$?
check "script called through a symlink"      '(( RC == 0 )) && has "All done."'

cd $WORK                                      # outside the project from here on
rm -rf -- $P/PDF
nbr -n proj
check "project dir argument"                 '(( RC == 0 )) && (( $(listed) == 6 )) && has "project: $P"'
nbr $RUNARGS proj
check "run with project dir argument"        '(( RC == 0 )) && has "All done." && (( $(count $P/.nb2cleanpdf/<->-<->(N/)) >= 1 ))'
if [[ $ENGINE != none ]]; then
  check "PDFs land in the project's PDF/"    'is_pdf $P/PDF/intro.pdf && [[ ! -e $WORK/PDF ]]'
  nbr $RUNARGS --no-exec -o rel-out proj
  check "-o is relative to where you are"    '(( RC == 0 )) && is_pdf $WORK/rel-out/intro.pdf'
fi
nbr -n does-not-exist
check "unknown project dir is an error"      '(( RC == 1 )) && has "not a directory"'
nbr -n proj venvs
check "only one project dir accepted"        '(( RC == 1 )) && has "only one project directory"'
nbr -y --no-pdf venvs/empty
check "install hint works from elsewhere"    '(( RC == 1 )) && has "venvs/empty && uv pip install --python .venv jupyter"'
nbr clean -n proj
check "clean with project dir argument"      '(( RC == 0 )) && has "nb2cleanpdf clean — $P"'
cd $P

# ---------- failures ------------------------------------------------------------------
section "failure handling"
cp -- scratch/broken.ipynb $WORK/broken.orig && cp -- scratch/slow.ipynb $WORK/slow.orig
nbr -y -t 3 -i scratch $PDFARGS
check "exit status 1"                        '(( RC == 1 )) && has "2 notebook(s) had errors"'
check "cell error summarised"                'has "execution failed" && has "ZeroDivisionError"'
check "timeout reported"                     'has "cell timed out"'
check "originals untouched on failure"       'cmp -s scratch/broken.ipynb $WORK/broken.orig && cmp -s scratch/slow.ipynb $WORK/slow.orig'
check "partial copies saved"                 '(( $(count .nb2cleanpdf/*/failed/*.ipynb(N)) >= 2 ))'
[[ $ENGINE != none ]] && \
check "PDF skipped after failed execution"   'has "PDF skipped"'
check "no colour codes when redirected"      '[[ $OUT != *$'"'\e'"'* ]]'
check "logs are plain text"                  '! command grep -q $'"'\e'"' .nb2cleanpdf/*/logs/*.log'

nbr_tty -y -t 3 -i slow --no-pdf
check "colours kept on a terminal"           '[[ $OUT == *$'"'\e[31m'"'* ]]'
check "progress clock ticks during a cell"   'has "(2s)"'

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
"$NB2CLEANPDF" -y -i long --no-pdf </dev/null >$WORK/long.out 2>&1 &
LONG=$!
for i in {1..60}; do            # wait until the exec helper is running
  command ps -U $UID -o command= | command grep -q "nb2cleanpdf\.$LONG\..*exec\.py" && break
  sleep 0.5
done

nbr clean -n
check "live run is detected and kept"        'has "in progress" && has "live"'
kill -9 $LONG 2>/dev/null; wait $LONG 2>/dev/null; sleep 1
nbr clean -n
check "orphans found after kill -9"          'has "Orphaned processes" && has "Orphaned temp dirs"'
nbr clean -y --keep 1
check "clean removes orphans"                '(( RC == 0 )) && has "Clean."'
check "no orphaned processes remain"         '! command ps -U $UID -o command= | command grep -q "nb2cleanpdf\.$LONG\."'
check "orphaned temp dir removed"            '(( $(count ${${TMPDIR:-/tmp}%/}/nb2cleanpdf.$LONG.*(N)) == 0 ))'
check "--keep 1 kept one run record"         '(( $(count .nb2cleanpdf/<->-<->(N/)) == 1 ))'

if [[ $ENGINE != none ]]; then
  nbr clean -n --pdfs -e scratch
  check "clean --pdfs lists exported PDFs"   'has "Exported PDFs" && has "intro.pdf"'
  nbr clean -y --pdfs
  check "clean --pdfs removes them"          '(( RC == 0 )) && [[ ! -e PDF/intro.pdf ]]'
  check "emptied PDF folders removed"        '[[ ! -e PDF/analysis/sub ]]'
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
