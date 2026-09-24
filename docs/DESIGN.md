# nb2cleanpdf — requirements and design decisions

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
10. PDFs go to `PDF/` in the project by default (`-o DIR` to change); the project can be
    given as an argument, and the script works from wherever it is installed.

Name: `nb2cleanpdf` (was `nbrerun`) — the goal is a clean PDF of each notebook.

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
8. `$TMP` workspace, traps, embedded Python helpers (`preview.py`, `exec.py`, `pw_pdf.py`,
   `chrome_pdf.py`).
9. Interactive (un)selection.
10. Run loop.
11. Summary.

## Venv and reproducibility

- "Created by uv": `pyvenv.cfg` has a `uv = …` line and `bin/python` is executable.
- Execution uses **nbclient directly** (`exec.py`), not `nbconvert --execute`: clears outputs,
  `execution_count` and `metadata.execution`; `record_timing=False`; fresh kernel per notebook;
  cwd = notebook directory.
- Throw-away kernelspec `nb2cleanpdf-$$` in `$TMP/jupyter/kernels/` (prepended to `JUPYTER_PATH`)
  so a user-level `python3` kernelspec can't shadow the venv interpreter. The notebook's
  original kernelspec metadata is restored before saving.
- Kernel env: `VIRTUAL_ENV` + `PATH` point at the venv (`!pip`, `subprocess` resolve to it);
  `MPLBACKEND` (macosx would open windows) and `PYTHONSTARTUP` unset; warning if `PYTHONPATH`
  is set; `JUPYTER_PLATFORM_DIRS=1`, `PYDEVD_DISABLE_FILE_VALIDATION=1`.
- Non-Python kernels are skipped (rc 3).

## Safety of user files

- The original is only replaced after a fully successful run: write `.<name>.nb2cleanpdf-tmp`,
  `copymode`, `os.replace` (atomic).
- On failure/timeout/Ctrl-C the original is untouched; a partial copy goes to
  `.nb2cleanpdf/<ts>/failed/NNN_<slug>.ipynb`.
- Backups on by default: `.nb2cleanpdf/<ts>/backup/<relpath>` (old outputs may be irreplaceable).
- `exec.py` return codes: 0 ok, 1 cell error, 2 other, 3 skipped, 4 timeout, 5 dead kernel.
- **No sandbox (decided).** Notebook code runs with the user's full permissions, same trust
  model as Jupyter's *Run All*; the README says so. The kernel-env tweaks above are for
  reproducibility, not security. Rejected: `sandbox-exec` (deprecated, macOS-only; Linux would
  need bwrap/firejail), containers (break the venv/uv/Chrome pipeline), pre-run "dangerous
  code" scans (trivially bypassed, false assurance), a per-run warning banner (noise).
  Notebooks legitimately need network, `~/.cache` and data outside the project, so any
  profile tight enough to matter breaks real ones.

## Project directory and paths

- `nb2cleanpdf [DIR]` / `nb2cleanpdf clean [DIR]`: a positional argument that is an existing
  directory is the project; anything else still gets the "quote your pattern" error.
- Paths in options (`-o`, `--venv`, `--browser`) are resolved against the invocation dir *before*
  the script `cd`s into the project; everything else (`.venv`, notebooks, `PDF/`,
  `.nb2cleanpdf/`) is relative to the project.
- Dependency install commands for the venv get a `cd <project> && ` prefix when the project is
  not the current dir, so the printed command works when pasted — and is still exactly what runs.
- Default output dir is `<project>/PDF` (mirrors the folder layout; pruned from discovery).
  `-o .` inside the project restores "next to each notebook". `clean --pdfs` removes PDF
  folders that end up empty (never the project dir itself).
- Nothing depends on where the script file lives (`$0` is only used for the program name).

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
  `pw_pdf.py` drives the installed browser with playwright (`launch(executable_path=…)`):
  `goto(wait_until="networkidle")`, then waits for MathJax's queue to drain, then
  `page.pdf(print_background=True)` (no header/footer by default), then `browser.close()`.
  - Why playwright: exact "page is ready" signal instead of a time budget, and a clean browser
    shutdown via CDP (the CLI printing hangs on Chrome 153, see below). Temporary profile, as always.
  - playwright is **not** installed into the venv: it runs from an ephemeral env in uv's cache
    (`uv run --no-project --python .venv/bin/python --with 'playwright>=1.49'`), so the project's
    venv, `pyproject.toml` and `uv.lock` stay untouched. The dependency check runs the same
    command with `--offline`; the export itself also runs `--offline` (no network round-trip).
- **chrome-cli**: same HTML, printed by `chrome_pdf.py` via the browser's own
  `--headless=new --print-to-pdf`, a temporary
  `--user-data-dir` (never the real profile; works while Chrome is open), no header/footer,
  `--virtual-time-budget=20000` for MathJax, injected `print-color-adjust: exact`.
  - **Chrome may never exit after printing** (seen with Chrome 153 on macOS 27: the PDF is
    complete after ~1 s, the process hangs forever, for any flags/content). So `chrome_pdf.py`
    doesn't wait for the process: it polls until the PDF ends with `%%EOF` and its size is
    stable, then terminates the browser's whole process group (started with
    `start_new_session`), also on timeout and Ctrl-C.
  - nbconvert's `WebPDFExporter` can't be pointed at an installed browser (no channel/executable
    option), hence the separate step.
- Browser discovery (chrome and chrome-cli): Chrome, Chromium, Edge, Brave, Chrome Beta, Canary in `/Applications`, then
  `~/Applications`, then PATH names (Linux). `--browser` takes a binary or `.app`.
- **webpdf**: playwright's own Chromium in the shared cache `~/Library/Caches/ms-playwright`.
- **latex**: fails on CJK with the default template.
- nbconvert always writes to `$TMP/pdf/<i>/out.*`, then the PDF is moved (webpdf's extension is
  `.html`, so `--output name.pdf` would give `name.pdf.pdf`; dotted names get mangled).
  nbconvert runs inside the notebook's directory so relative image paths resolve.
- PDF export is skipped when execution failed. LaTeX failures show the deduplicated `! …` lines.

## Run bookkeeping

- `$TMP = $TMPDIR/nb2cleanpdf.<pid>.XXXXXX` (pid lets `clean` tell live from orphaned runs). The EXIT
  trap removes `$TMP` and `$RUN_DIR/.pid`.
- `.nb2cleanpdf/<YYYYmmdd-HHMMSS>/`: `logs/`, `backup/`, `failed/`, `.pid` (marks a live run).
- Ctrl-C: `trap 'INTERRUPTED=1' INT`; the foreground helper gets SIGINT, the notebook stays
  untouched, the summary is printed, exit 130.
- No spinners/background jobs (a non-interactive shell's background jobs ignore SIGINT).
  Progress is written by `exec.py` to fd 3 and redrawn with `\r\e[K`: on every cell start and
  once a second from a daemon thread, so the clock keeps running through kernel start-up and
  long cells.
- Colours: stdout and stderr are coloured only when they are terminals (checked separately).
  Tracebacks from IPython carry their own ANSI codes: the on-screen error summary keeps them on a
  terminal and strips them otherwise; logs are always written as plain text.

## `nb2cleanpdf clean`

| Leftover | Rule |
|---|---|
| run records `.nb2cleanpdf/<ts>/` | newest first, `--keep N`; live runs never touched |
| `.*.ipynb.nb2cleanpdf-tmp` | skipped while any run is live |
| temp dirs `$TMPDIR/nb2cleanpdf.<pid>.*` | owner pid dead |
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
- 2026-09-23: chrome engine switched to playwright; verified on the Mac (Chrome exits cleanly,
  ~3 s per PDF), plus the missing-playwright install flow with an empty uv cache.
