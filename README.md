# All Skills

All Skills 是可复用 AI Agent Skills 仓库，用来集中维护、安装和同步团队常用 skills。

核心原则：**本仓库是唯一真实来源，CLI 的 skill 目录只链接回本仓库**。

## 快速入口

- 分类规划：[docs/CATEGORIES.md](docs/CATEGORIES.md)
- Skill 创建与更新规范：[docs/SKILL_GUIDE.md](docs/SKILL_GUIDE.md)
- 新 skill 模板：[templates/new-skill/SKILL.md](templates/new-skill/SKILL.md)
- Agent 协作规则：[AGENTS.md](AGENTS.md)

## 目录约定

```text
skills/<function>/<domain>/<skill>/SKILL.md
```

- `function`：职能分类，例如 `engineering`、`marketing`、`operations`。
- `domain`：主题领域，例如 `engineering/code-review`。
- `skill`：具体能力，目录内必须包含 `SKILL.md`。

```text
all-skills/
├── skills/       # skill 源文件
├── docs/         # 规范和操作手册
├── templates/    # 新 skill 模板
├── scripts/      # 安装、更新、卸载、检查脚本
├── sources/      # 第三方 skill 来源声明
├── tools/        # skillctl 等维护工具
└── .xan/         # 第三方 skill 锁定信息
```

顶层分类：`engineering`、`marketing`、`ecommerce`、`operations`、`content`、`media`、`data`、`finance`、`legal`、`customer-support`、`productivity`、`platforms`。

## 安装

Linux、macOS、WSL：

```bash
bash scripts/install.sh
```

在终端里先选安装目标，再进入交互式列表：`↑↓` 移动，空格切换，`a` 全选，`n` 清空，`r` 还原，回车应用，`q` 取消。右侧面板显示当前光标所在 skill 的分类、来源、安装状态和一句话简介，简介取自 [docs/CATEGORIES.md](docs/CATEGORIES.md) 的说明列，缺失时回退到 `SKILL.md` 里 `description` 的第一句。

勾选框直接表示该 skill 在目标目录里的最终状态，回车后按差异执行：

| 标记 | 含义 |
|---|---|
| `[x]` | 已安装，保持不动 |
| `[+]` | 未安装，本次新增 |
| `[-]` | 已安装但取消了勾选，本次移除软链接（会二次确认） |
| `[ ]` | 未安装，也不装 |

目标位置被真实目录或指向别处的软链接占用时，该行标黄。这类条目不会被自动删除；只有勾选它才会改写成指向本仓库，真实目录则始终跳过。

管道、CI 或 `NO_TUI=1` 下自动退回编号输入模式。编号模式只做安装，不做移除，列表里用 `[已装]`、`[位置被占用]` 标注当前状态。

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

PowerShell 版本仍是编号输入，没有交互式面板。

## 更新与检查

```bash
git pull --ff-only
bash scripts/update.sh
bash scripts/doctor.sh
```

## 第三方 Skill

第三方 skill 通过 `sources/skills.sources.yaml` 声明来源，通过 `.xan/skills.lock.json` 锁定版本，并作为已审核快照同步到 `skills/`。

```bash
npm install
./skillctl check
./skillctl update <skill-name>
./skillctl update --all --dry-run
./skillctl sync
./skillctl doctor
```

不要手工修改第三方快照目录。需要本地适配时，优先使用 `overlays/<skill-name>/overlay.yaml`。

## 修改与发布

```bash
git status --short
bash scripts/doctor.sh
git add skills sources .xan overlays tools test docs templates scripts .github package.json package-lock.json AGENTS.md README.md
git commit -m "update skills"
git push
```

## 卸载

```bash
bash scripts/uninstall.sh
```

卸载脚本只删除目标目录里的链接，不会删除本仓库里的 skill 源文件。

## 维护原则

- README 只保留入口说明和常用命令。
- 具体操作手册、设计说明和规范放在 `docs/` 下。
- 新增或更新 skill 时，以 [docs/SKILL_GUIDE.md](docs/SKILL_GUIDE.md) 为准。