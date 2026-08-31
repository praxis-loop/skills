# oazon-mm-daily-log Windows 兼容与正文精简设计

## 目标

只处理两项：修复 `fetch_mm_day.py` 在 Windows 下调用 OpenCLI 的兼容问题；精简 `SKILL.md`，降低每次触发时的上下文开销。日报抓取范围、归纳口径、输出格式和写入审批流程保持不变。

## Windows 兼容

### 根因

Windows 的 npm 安装同时提供无扩展名脚本、PowerShell 脚本和 `.cmd` 包装器。Python `subprocess` 直接执行 `opencli` 时可能找不到可执行文件；改用 `.cmd` 后，多行 JavaScript 又会被批处理 `%*` 转发破坏。Python 文本管道还会默认按系统代码页解码 OpenCLI 的 UTF-8 输出。

### 方案

在抓取脚本中增加两个小边界：

1. `resolve_opencli_command()` 返回 OpenCLI 命令前缀。
   - 非 Windows：使用 PATH 中的 `opencli`。
   - Windows：定位 `node.exe`，再从 npm shim 所在目录定位 `node_modules/@jackwener/opencli/dist/src/main.js`，直接调用 Node 入口，绕过 `.cmd` 参数转发。
   - 任一依赖缺失时给出明确错误，不写死当前机器路径。
2. `run_opencli()` 统一执行命令，显式设置 `encoding="utf-8"`，保留现有超时、返回码和错误信息处理。

`open_site()` 和 `run_eval()` 只负责组装各自参数，避免重复平台判断。

### 测试

先添加失败测试，再实现：

- Windows 能解析为 `node.exe + OpenCLI main.js`，不会返回 `.cmd` 包装器。
- 非 Windows 仍直接使用 `opencli`。
- Unicode 输出可在系统默认代码页不是 UTF-8 时正确读取。
- 现有日期边界与 JSON 载荷提取行为保持不变。

## SKILL.md 精简

### 目标

将正文从 143 行压缩到约 80 行，并减少重复规则；不以牺牲安全边界和日报质量为代价。

### 保留内容

- 默认日期、个人视角和约 8h 口径。
- 只读 Mattermost、使用会话 scratchpad、完整读取相关消息。
- 只写本人经手、拍板或驱动的工作。
- 项目短名、子条目不超过 30 字、保留数字、使用真实 Boost 链接。
- `daily.md` 写入前备份、生成 diff、验算工时、用户确认后落盘。
- 抓取量级、工作时段、身份和日期的完整性检查。

### 删除或下沉内容

- 合并“输出要求”“检查项”“边界”中的重复表述。
- 删除正文内重复出现的格式示例和解释。
- `report-format.md` 仅在生成草稿时读取。
- `mattermost-api.md` 仅在抓取量、分页或日界线异常时读取。
- `daily-md.md` 仅在用户要求写入时读取。
- 长样例和反例继续留在引用文件，不复制回主技能。

### 契约测试

添加文档测试，要求：

- `SKILL.md` 不超过 100 行且体积不超过 6KB。
- 保留关键短语或等价规则：只写本人、完整读取、约 8h、30 字、真实 Boost 链接、备份、diff、用户确认、只读 Mattermost。
- 引用三个参考文件，并明确各自的按需读取条件。

## 非目标

- 不新增紧凑事件产物，不修改 `mine.txt`、`posts.json` 或频道抓取结构。
- 不改变默认截断长度、线程补全、噪音过滤或工时分配逻辑。
- 不写入 `daily.md`，不操作 Mattermost 内容。
- 不提交或推送 Git 变更，除非用户另行要求同步。

## 验收

1. 新增测试先在旧实现上失败，再在新实现上通过。
2. Windows 使用真实 OpenCLI 会话完成最小 `users/me` 读取。
3. 抓取脚本帮助信息和日期边界测试通过。
4. 技能正文契约测试通过。
5. `bash scripts/doctor.sh` 通过。
6. 最终汇报工作树是否存在未提交、未推送或待拉取变更。
