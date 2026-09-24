"""Create the notebook fixture used by tests/run-tests.zsh.

Usage: python make_fixture.py DIR
"""
import sys
from pathlib import Path

import nbformat as nbf


def mk(root: Path, rel: str, cells: list[str], title: str | None = None) -> None:
    nb = nbf.v4.new_notebook()
    nb.metadata["kernelspec"] = {"name": "python3", "display_name": "Python 3", "language": "python"}
    md = f"# {title or rel}\n\nEuler: $e^{{i\\pi}}+1=0$"
    nb.cells = [nbf.v4.new_markdown_cell(md)] + [nbf.v4.new_code_cell(c) for c in cells]
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    nbf.write(nb, path)


def main() -> None:
    root = Path(sys.argv[1])
    mk(root, "intro.ipynb", [
        "import os, sys\nprint('CWD=' + os.getcwd())\nprint('EXE=' + sys.executable)",
        "print('hello-from-intro')",
    ])
    mk(root, "analysis/fig 1.v2.ipynb", [
        "import numpy as np, matplotlib.pyplot as plt\nplt.plot(np.arange(10)); plt.title('line'); plt.show()",
        "open('local.txt', 'w').write('cwd check')",
    ])
    mk(root, "analysis/sub/eda.ipynb", ["print('eda-output-ok')"])
    mk(root, "unicode/cjk.ipynb", ["print('中文 ok')"], title="unicode/cjk.ipynb 中文")
    mk(root, "scratch/broken.ipynb", ["print('before')", "1/0", "print('never-reached')"])
    mk(root, "scratch/slow.ipynb", ["import time; time.sleep(30)"])


if __name__ == "__main__":
    main()
