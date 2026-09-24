# nb2cleanpdf — notes for agents

- Reply to the user in Simplified Chinese; code, comments, CLI help and terminal messages stay English.
- `nb2cleanpdf` is intentionally ONE self-contained zsh file (Python helpers are embedded as heredocs
  and written to `$TMP` at runtime). Don't split it without asking.
- `install.sh` is POSIX sh (runs via `curl | sh`, dash on Linux). It recognises the script by its
  3rd line starting with `# nb2cleanpdf — ` — keep that header line.
- `README.md` (English) and `README.zh-CN.md` (简体中文) must stay in sync: any change to one —
  content, options, examples, badges — goes into the other in the same commit.
- Releasing: bump `VERSION=` in `nb2cleanpdf`, merge, then tag `v<VERSION>` on that commit and
  create the GitHub release with `nb2cleanpdf` and `install.sh` attached (see `docs/DESIGN.md`).
- Read `docs/DESIGN.md` before changing behaviour — most "obvious improvements" collide with a recorded decision.

## Invariants
- A notebook is never overwritten unless execution fully succeeded.
- Commands shown in dependency hints are exactly the commands executed (`eval`, `${(q)…}` quoting).
- Nothing is installed or deleted without consent (or `--install-deps` / `-y`). No `curl | bash`.
- `nb2cleanpdf clean` never touches a live run.

## Style
- `emulate -R zsh`, `extended_glob`, `pipe_fail`, no `nounset`; `print -r --`; `command find/grep`.
- No GNU-only tools/flags (no `timeout`, `sed -i`, `readlink -f`); must work with macOS BSD userland.
- No backgrounded jobs/spinners in the script (breaks Ctrl-C); progress comes from the helper via fd 3.

## Checking changes
- `zsh -n nb2cleanpdf` exits 1 after any `! cmd` even with valid syntax — treat "prints nothing" as success.
- `tests/run-tests.zsh --engine auto|chrome|chrome-cli|webpdf|latex|none` — functional suite, work dir `tests/.work/`.
- CI runs lint + the suite per engine (see `.github/workflows/ci.yml`).
