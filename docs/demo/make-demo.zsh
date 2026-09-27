#!/usr/bin/env zsh
# Build the small project recorded in docs/images/ (see demo.tape).
# Usage: docs/demo/make-demo.zsh DIR      (DIR must not exist yet)
emulate -R zsh
setopt err_exit pipe_fail
(( $# == 1 )) || { print -ru2 -- "usage: ${0:t} DIR"; exit 2 }
[[ -e $1 ]] && { print -ru2 -- "${0:t}: $1 already exists"; exit 1 }
mkdir -p -- $1 && cd -- $1
uv init --bare -q
uv add --dev -q jupyter numpy matplotlib
uv run -q python - <<'PYEOF'
from pathlib import Path
import nbformat as nbf

def mk(rel, title, cells):
    nb = nbf.v4.new_notebook()
    nb.metadata["kernelspec"] = {"name": "python3", "display_name": "Python 3", "language": "python"}
    nb.cells = [nbf.v4.new_markdown_cell(f"# {title}")] + [nbf.v4.new_code_cell(c) for c in cells]
    Path(rel).parent.mkdir(parents=True, exist_ok=True)
    nbf.write(nb, rel)

mk("01-load-data.ipynb", "Load data", [
    "import numpy as np\nrng = np.random.default_rng(0)\nx = rng.normal(size=1000)",
    "import time; time.sleep(2)  # pretend to download something",
    "print(f'{x.size} samples, mean {x.mean():.3f}')",
])
mk("analysis/plots.ipynb", "Plots", [
    "import numpy as np, matplotlib.pyplot as plt",
    "t = np.linspace(0, 2 * np.pi, 200)\nplt.plot(t, np.sin(t)); plt.title('sin'); plt.show()",
    "import time; time.sleep(2)",
])
mk("analysis/stats.ipynb", "Summary statistics  $\\bar x = \\frac1n\\sum x_i$", [
    "import numpy as np\nx = np.arange(10)",
    "print('mean', x.mean(), 'std', round(x.std(), 3))",
])
mk("scratch/broken.ipynb", "Work in progress", [
    "data = {'a': 1}",
    "print(data['b'])",
])
mk("scratch/draft.ipynb", "Draft", ["print('not ready')"])
PYEOF
print -r -- "demo project ready: $PWD"
