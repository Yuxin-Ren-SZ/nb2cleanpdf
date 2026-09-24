# nb2cleanpdf

[![CI](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/actions/workflows/ci.yml/badge.svg)](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/actions/workflows/ci.yml)
![platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue)
![shell: zsh](https://img.shields.io/badge/shell-zsh-4EAA25)
[![venv: uv](https://img.shields.io/badge/venv-uv-DE5FE9?logo=uv&logoColor=white)](https://docs.astral.sh/uv/)
![Jupyter notebooks](https://img.shields.io/badge/Jupyter-notebooks-F37626?logo=jupyter&logoColor=white)
[![last commit](https://img.shields.io/github/last-commit/Yuxin-Ren-SZ/nb2cleanpdf)](https://github.com/Yuxin-Ren-SZ/nb2cleanpdf/commits/main)

[English](README.md) | **简体中文**

把 Jupyter notebook 导出成**干净的 PDF**：用项目自己的 **uv** 虚拟环境把项目里的每个
notebook 从头重新运行一遍，然后导出为 PDF（放在 `PDF/` 目录下）。

- 找出所有 `.ipynb` 文件（跳过隐藏目录、`.venv`、`node_modules` 和 checkpoint 文件）
- 可以取消勾选不想处理的 notebook（fzf 选择器，或编号菜单），也可以用 `-i` / `-e` 模式过滤
- 每个 notebook 都在 `./.venv` 的全新 kernel 中运行：先清空旧输出，工作目录设为 notebook 所在文件夹
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

运行要求：zsh、[uv](https://docs.astral.sh/uv/)，以及项目中由 uv 创建的 `.venv`。
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
```

项目目录（默认为当前目录）包含 `.venv`、notebook、`PDF/`，以及 `.nb2cleanpdf/` 中的运行记录。
选项中的路径（`-o`、`--venv`、`--browser`）相对于你执行命令时所在的目录。

模式一定要加引号。不含通配符的普通词匹配路径中的任意位置；含 `/` 的通配符匹配整个相对路径；
不含 `/` 的通配符只匹配文件名。

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
