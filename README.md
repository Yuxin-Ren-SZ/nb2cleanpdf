# nbrerun

Cleanly re-run every Jupyter notebook below the current directory with the
project's **uv** virtualenv, then export each one to **PDF**.

- finds all `.ipynb` files (skips hidden dirs, `.venv`, `node_modules`, checkpoints)
- lets you unselect notebooks (fzf picker, or a numbered menu) and filter with `-i` / `-e` patterns
- runs each notebook in a fresh kernel from `./.venv`, with outputs cleared first and cwd set to the notebook's folder
- only overwrites a notebook when it ran without errors (atomic replace, backup kept in `.nbrerun/`)
- exports PDFs by reusing the Chrome/Edge/Brave you already have installed (no browser download)
- checks every dependency at start-up and offers to install what's missing
- `nbrerun clean` removes run records and whatever a killed run left behind

It's a single self-contained zsh script for macOS (Linux works too).

## Install

```zsh
cp nbrerun ~/.local/bin/        # or anywhere on your PATH
```

Requirements: zsh, [uv](https://docs.astral.sh/uv/), and a uv-created `.venv` in the
project. Everything else (jupyter, fzf, …) is checked at start-up, with the command that
installs it.

## Usage

```zsh
cd my-research-project
nbrerun                          # pick notebooks, re-run them, export PDFs
nbrerun -n                       # just list what would be processed
nbrerun -i 'analysis/*' -e '(#i)*draft*' -o pdf -t 900
nbrerun clean -n                 # show leftovers; `nbrerun clean` removes them
nbrerun -h                       # all options
```

Always quote patterns. A plain word matches anywhere in the path; a glob with `/`
matches the whole relative path; a glob without `/` matches the file name.

## PDF engines

| `--engine` | how | needs |
|---|---|---|
| `auto` (default) | `chrome` if a Chromium-based browser is installed, else `webpdf` | |
| `chrome` | nbconvert HTML, printed by your installed browser driven by playwright | Chrome / Edge / Brave / Chromium; playwright is fetched once into uv's cache (~300 MB), never added to your venv |
| `chrome-cli` | same, via the browser's own `--headless --print-to-pdf` | the browser only |
| `webpdf` | nbconvert + playwright's own Chromium | `nbconvert[webpdf]`, ~150 MB download (shared cache) |
| `latex` | nbconvert + xelatex (no CJK support) | pandoc, a TeX distribution |

Formulas are rendered with MathJax from a CDN, so PDF export needs network access.

## Development

```zsh
tests/run-tests.zsh --engine auto    # builds a scratch project in tests/.work/ and runs ~50 checks
tests/run-tests.zsh --engine none    # skip PDF export (fast)
```

CI (`.github/workflows/ci.yml`) runs the suite for every engine on Linux and the
browser engines on macOS; PDFs and logs are uploaded as build artifacts.

Design decisions and their reasons: [docs/DESIGN.md](docs/DESIGN.md).
