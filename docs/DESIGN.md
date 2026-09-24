# nbrerun — requirements and design decisions

## Requirements (from the user)

1. Find every `.ipynb` below the current directory.
2. Re-run them one by one, cleanly, to reproduce a clean result.
3. Run them with the **uv-created** venv in the current directory; error out if there is none.
4. Export all notebooks to PDF; report every error.
5. After discovery, the user can **unselect** notebooks.
6. `-i` / `-e` include/exclude patterns.
7. Check every dependency at start-up and say how to install what's missing; offer to install
   it (`y` installs, `n` exits; the manual commands stay visible). Propose tools that help.
8. Don't download a browser per project — reuse the installed Chrome.
9. A `clean` command that checks for leftovers, then removes them.

Target: macOS, Ghostty, zsh 5.9, Homebrew, uv. Notebooks are research notebooks with plots,
formulas and relative paths.

## Layout of the script (top → bottom)

1. Header, `emulate -R zsh`, options, colours (TTY only), `info/warn/die/hint`, `usage`.
2. Manual `while/case` argument parser (predictable `--opt=val`, clear errors; not `zparseopts`).
3. Shared helpers: `discover`, `matches_any`, `filter_notebooks`.
4. `clean` subcommand — runs and exits **before** venv/dependency checks, so it works anywhere.
5. uv venv validation.
6. Dependency registry, check → report → prompt → install loop, engine resolution, `--sync`.
7. Discover + filter, dry-run exit.
8. `$TMP` workspace, traps, embedded Python helpers (`preview.py`, `exec.py`, `chrome_pdf.py`).
9. Interactive (un)selection.
10. Run loop.
11. Summary.

## Venv and reproducibility

- "Created by uv": `pyvenv.cfg` has a `uv = …` line and `bin/python` is executable.
- Execution uses **nbclient directly** (`exec.py`), not `nbconvert --execute`: clears outputs,
  `execution_count` and `metadata.execution`; `record_timing=False`; fresh kernel per notebook;
  cwd = notebook directory.
- Throw-away kernelspec `nbrerun-$$` in `$TMP/jupyter/kernels/` (prepended to `JUPYTER_PATH`)
  so a user-level `python3` kernelspec can't shadow the venv interpreter. The notebook's
  original kernelspec metadata is restored before saving.
- Kernel env: `VIRTUAL_ENV` + `PATH` point at the venv (`!pip`, `subprocess` resolve to it);
  `MPLBACKEND` (macosx would open windows) and `PYTHONSTARTUP` unset; warning if `PYTHONPATH`
  is set; `JUPYTER_PLATFORM_DIRS=1`, `PYDEVD_DISABLE_FILE_VALIDATION=1`.
- Non-Python kernels are skipped (rc 3).

## Safety of user files

- The original is only replaced after a fully successful run: write `.<name>.nbrerun-tmp`,
  `copymode`, `os.replace` (atomic).
- On failure/timeout/Ctrl-C the original is untouched; a partial copy goes to
  `.nbrerun/<ts>/failed/NNN_<slug>.ipynb`.
- Backups on by default: `.nbrerun/<ts>/backup/<relpath>` (old outputs may be irreplaceable).
- `exec.py` return codes: 0 ok, 1 cell error, 2 other, 3 skipped, 4 timeout, 5 dead kernel.

## Discovery and patterns

- `find -print0` split with `(0)`; hidden dirs, `node_modules`, `__pycache__`, `site-packages`,
  the venv and the PDF output dir are pruned; `-iname '*.ipynb'` minus `*-checkpoint.ipynb`.
- Plain word → substring of the relative path; glob with `/` → whole path; glob without `/` →
  file name; `(#i)` → case-insensitive. A stray positional argument means an unquoted glob.

## Selection UI

- fzf ≥ 0.36 (`load:select-all`), preview from `preview.py`. A `[Y/n]` confirmation always
  follows (Enter with nothing selected returns the focused line in `--multi` mode).
- Without fzf: numbered list, type numbers/ranges to exclude. Skipped with `-y` or no TTY.

## Dependencies

- Registry `add_dep name required auto cmd why note`; `ensure_deps` loops up to 3 rounds.
- The command shown is exactly the command executed. Optional-only (fzf) → one-line tip, never
  a prompt. No TTY and no `--install-deps` → list and exit 1. Stop at the first failing install.
- uv: `uv add --dev …` with a `pyproject.toml` (a later `uv sync` keeps it), else
  `uv pip install --python .venv …`; `UV_PROJECT_ENVIRONMENT` when `--venv` isn't `.venv`.
- Homebrew is never auto-installed (no `curl | bash`).
- LaTeX: checks `pandoc`, `xelatex`, and the `.sty` files via `kpsewhich` (BasicTeX lacks e.g.
  `ulem.sty`); `/Library/TeX/texbin` is added to PATH.

## PDF engines

- **chrome** (default via `auto`): `nbconvert --to html --template webpdf --embed-images`, then
  `chrome_pdf.py` prints with the installed browser: `--headless=new --print-to-pdf`, a temporary
  `--user-data-dir` (never the real profile; works while Chrome is open), no header/footer,
  `--virtual-time-budget=20000` for MathJax, injected `print-color-adjust: exact`.
  - **Chrome may never exit after printing** (seen with Chrome 153 on macOS 27: the PDF is
    complete after ~1 s, the process hangs forever, for any flags/content). So `chrome_pdf.py`
    doesn't wait for the process: it polls until the PDF ends with `%%EOF` and its size is
    stable, then terminates the browser's whole process group (started with
    `start_new_session`), also on timeout and Ctrl-C.
  - nbconvert's `WebPDFExporter` can't be pointed at an installed browser (no channel/executable
    option), hence the separate step.
- Browser discovery: Chrome, Chromium, Edge, Brave, Chrome Beta, Canary in `/Applications`, then
  `~/Applications`, then PATH names (Linux). `--browser` takes a binary or `.app`.
- **webpdf**: playwright's own Chromium in the shared cache `~/Library/Caches/ms-playwright`.
- **latex**: fails on CJK with the default template.
- nbconvert always writes to `$TMP/pdf/<i>/out.*`, then the PDF is moved (webpdf's extension is
  `.html`, so `--output name.pdf` would give `name.pdf.pdf`; dotted names get mangled).
  nbconvert runs inside the notebook's directory so relative image paths resolve.
- PDF export is skipped when execution failed. LaTeX failures show the deduplicated `! …` lines.

## Run bookkeeping

- `$TMP = $TMPDIR/nbrerun.<pid>.XXXXXX` (pid lets `clean` tell live from orphaned runs). The EXIT
  trap removes `$TMP` and `$RUN_DIR/.pid`.
- `.nbrerun/<YYYYmmdd-HHMMSS>/`: `logs/`, `backup/`, `failed/`, `.pid` (marks a live run).
- Ctrl-C: `trap 'INTERRUPTED=1' INT`; the foreground helper gets SIGINT, the notebook stays
  untouched, the summary is printed, exit 130.
- No spinners/background jobs (a non-interactive shell's background jobs ignore SIGINT).
  Progress is written by `exec.py` to fd 3 and redrawn with `\r\e[K`.

## `nbrerun clean`

| Leftover | Rule |
|---|---|
| run records `.nbrerun/<ts>/` | newest first, `--keep N`; live runs never touched |
| `.*.ipynb.nbrerun-tmp` | skipped while any run is live |
| temp dirs `$TMPDIR/nbrerun.<pid>.*` | owner pid dead |
| processes | command line contains a dead run's temp-dir name; TERM, ~3 s, KILL |
| PDFs | only with `--pdfs`; `<stem>.pdf`, honouring `-o/-i/-e` |

Kernels need no handling (ipykernel exits when its parent dies). Records and PDFs go to the
Trash when a `trash` command exists (macOS 15+: `/usr/bin/trash`), otherwise deleted.

## Verification log

- 2026-09-23, macOS 27 / Chrome 153 / Ghostty: chrome engine (after the no-exit fix), PDF
  quality (plots, MathJax, CJK, backgrounds, no header/footer), real profile untouched, errors
  and timeouts, dependency install (`y`, `n`, `--install-deps`, no TTY), `clean` after
  `kill -9` (BSD `ps`, `/usr/bin/trash`), Ctrl-C and the fzf picker (by the user).
- Not verified on the Mac: webpdf and latex engines (covered by CI on Linux).
