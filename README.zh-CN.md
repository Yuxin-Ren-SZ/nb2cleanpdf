# nb2cleanpdf

[![CI](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/actions/workflows/ci.yml/badge.svg)](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/actions/workflows/ci.yml)
![platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue)
![shell: zsh](https://img.shields.io/badge/shell-zsh-4EAA25)
[![venv: uv](https://img.shields.io/badge/venv-uv-DE5FE9?logo=uv&logoColor=white)](https://docs.astral.sh/uv/)
![Jupyter notebooks](https://img.shields.io/badge/Jupyter-notebooks-F37626?logo=jupyter&logoColor=white)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![last commit](https://img.shields.io/github/last-commit/Yuxin-Ren-SZ/nb2cleanpdf)](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/commits/main)

[English](README.md) | **简体中文**

把 Jupyter notebook 导出成**干净的 PDF**：用项目自己的 **uv** 虚拟环境（或你指定的 venv / conda
环境）把项目里的每个 notebook 从头重新运行一遍，然后导出为 PDF（放在 `PDF/` 目录下）。

- 找出所有 `.ipynb` 文件（跳过隐藏目录、`.venv`、`node_modules` 和 checkpoint 文件）
- 可以取消勾选不想处理的 notebook（fzf 选择器，或编号菜单），也可以用 `-i` / `-e` 模式过滤
- 每个 notebook 都在 `./.venv`（或 `--env local PATH` / `--env conda NAME`）的全新 kernel 中运行：先清空旧输出，工作目录设为 notebook 所在文件夹
- 只有完整运行成功才会覆盖原 notebook（原子替换，并在 `.nb2cleanpdf/` 中保留备份）
- 复用你已安装的 Chrome / Edge / Brave 导出 PDF，按原文件夹结构放进 `PDF/`
- 启动时检查所有依赖，缺什么会给出安装命令，并询问是否帮你安装
- `nb2cleanpdf clean` 清理运行记录，以及被强行中断的运行留下的残余

这是一个独立的单文件 zsh 脚本，面向 macOS（Linux 也能用；两者都在 CI 中测试）。
不支持原生 Windows——WSL 可能可用，但未经测试。

## 安装

```zsh
curl -fsSL https://raw.githubusercontent.com/Yuxin-Ren-SZ/nb2cleanpdf/main/install.sh | sh
```

这会安装 `main` 分支上的最新代码。要固定某个
[发布版本](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/releases)，加上 `--version`：

```zsh
curl -fsSL https://raw.githubusercontent.com/Yuxin-Ren-SZ/nb2cleanpdf/main/install.sh | sh -s -- --version 0.3.0
```

或者从克隆的仓库安装：

```zsh
git clone https://github.com/Yuxin-Ren-SZ/nb2cleanpdf && cd nb2cleanpdf
./install.sh                 # 把 nb2cleanpdf 复制到 ~/.local/bin
./install.sh --link          # 改为软链接，之后 `git pull` 即可更新
./install.sh --prefix /usr/local        # 或 --bin-dir DIR
./install.sh --uninstall
```

安装脚本只会写入 `<bin 目录>/nb2cleanpdf`；同名文件如果不是 nb2cleanpdf，绝不覆盖
（除非加 `--force`）；bin 目录不在 `PATH` 里时会提醒你。

运行要求：zsh、[uv](https://docs.astral.sh/uv/)，以及项目中由 uv 创建的 `.venv`——也可以用其他环境，
见[运行环境](#运行环境)。
其他依赖（jupyter、fzf 等）都会在启动时检查，并给出对应的安装命令。

## 用法

```zsh
cd my-research-project
nb2cleanpdf                          # 选择 notebook，重新运行，导出 PDF 到 ./PDF/
nb2cleanpdf ~/research/other-proj    # 在任何位置处理另一个项目
nb2cleanpdf -n                       # 只列出将要处理的 notebook
nb2cleanpdf -i 'analysis/*' -e '(#i)*draft*' -o ~/Desktop/pdfs -t 900
nb2cleanpdf -o .                     # PDF 放在每个 notebook 旁边，而不是 PDF/
nb2cleanpdf clean -n                 # 查看残余文件；`nb2cleanpdf clean` 进行清理
nb2cleanpdf -h                       # 全部选项
nb2cleanpdf -V                       # 查看已安装的版本
```

项目目录（默认为当前目录）包含 `.venv`、notebook、`PDF/`，以及 `.nb2cleanpdf/` 中的运行记录。
选项中的路径（`-o`、`--env`、`--browser`、`--config`）相对于你执行命令时所在的目录。

模式一定要加引号。不含通配符的普通词匹配路径中的任意位置；含 `/` 的通配符匹配整个相对路径；
不含 `/` 的通配符只匹配文件名。

**只运行你信任的 notebook。** 每个代码单元都以当前用户的权限执行，与 Jupyter 中的 *Run All*
完全相同——没有任何沙箱隔离。处理来源不明的 notebook 之前，请先检查其中的代码。

## 运行环境

默认在项目的 uv 虚拟环境中运行 notebook。可以用 `--env` 选择其他环境：

```zsh
nb2cleanpdf                                  # --env uv：./.venv，必须由 uv 创建
nb2cleanpdf --env=uv:envs/py312              # 其他位置的 uv 虚拟环境（等同于 --venv DIR）
nb2cleanpdf --env local ./venv               # 任意 venv：python -m venv、virtualenv、poetry、pdm…
nb2cleanpdf --env conda myenv                # conda / mamba / micromamba 环境，按名称…
nb2cleanpdf --env conda ~/miniforge3/envs/x  # …或按路径
```

- conda 环境按 `conda activate` 的方式激活，包括其 `etc/conda/activate.d` 脚本和
  `conda env config vars` 设置的变量。
- 缺少的包用环境自己的工具安装——`uv`、venv 自带的 `pip`，或
  `conda` / `mamba` / `micromamba install -c conda-forge`。会先显示完整命令，
  你同意后才执行（或使用 `--install-deps`）。
- 如果环境不存在或类型不对，nb2cleanpdf 会停止并给出应改用的命令，绝不会自动换用其他环境。
- `chrome` PDF 引擎仍然需要 uv（playwright 从 uv 的缓存中运行）。

## 配置文件

可以把运行环境和其他默认设置写进配置文件。**只有**传入 `--config` 时才会读取；
命令行选项优先于配置文件。

```toml
# .nb2cleanpdf.toml（放在项目中；也可以是任意文件：--config path/to/file.toml）
env = "conda"
env_spec = "myenv"               # conda 名称/路径，或 venv 路径（相对于本文件）
engine = "chrome"
output_dir = "PDF"
timeout = 900
exclude = ["scratch", "(#i)*draft*"]
allow_errors = false
backup = true
```

```zsh
nb2cleanpdf --config                 # 读取 ./.nb2cleanpdf.toml
nb2cleanpdf --config ci.toml -e eda  # -e 会替换文件中的 exclude 列表
```

可用的键：`env`、`env_spec`、`engine`、`browser`、`output_dir`、`timeout`、`include`、
`exclude`、`allow_errors`、`backup`。格式是 TOML 的子集：只能是顶层的 `key = value` 行，
值为带引号的字符串、整数、`true`/`false`，或写在一行里的字符串数组。未知的键或其他写法都会报错。

## PDF 引擎

| `--engine` | 方式 | 需要 |
|---|---|---|
| `auto`（默认） | 装有 Chromium 系浏览器时用 `chrome`，否则用 `webpdf` | |
| `chrome` | nbconvert 生成 HTML，由 playwright 驱动你已安装的浏览器打印 | Chrome / Edge / Brave / Chromium；playwright 只下载一次到 uv 缓存（约 300 MB），不会加入你的 venv |
| `chrome-cli` | 同上，但用浏览器自带的 `--headless --print-to-pdf` | 只需浏览器 |
| `webpdf` | nbconvert + playwright 自带的 Chromium | `nbconvert[webpdf]`，约 150 MB 下载（共享缓存） |
| `latex` | nbconvert + xelatex（不支持中日韩文字） | pandoc 和 TeX 发行版 |

公式由 CDN 上的 MathJax 渲染，所以导出 PDF 需要联网。

## 开发

```zsh
tests/run-tests.zsh --engine auto    # 在 tests/.work/ 建一个临时项目，运行约 80 项检查
tests/run-tests.zsh --engine none    # 跳过 PDF 导出（更快）
```

CI（`.github/workflows/ci.yml`）在 Linux 上对每种引擎运行测试，在 macOS 上测试浏览器引擎；
生成的 PDF 和日志会作为构建产物上传。

设计决策及其原因见 [docs/DESIGN.md](docs/DESIGN.md)（英文）。

## 许可证

[MIT](LICENSE) © 2026 Yuxin Ren
