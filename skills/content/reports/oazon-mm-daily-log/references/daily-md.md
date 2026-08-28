# 写入 daily.md

草稿定稿后追加到 Obsidian 库里的日报文件。本文件记录该文件的既有约定——**这些约定是从文件里实测出来的，不是约定俗成，改动前先自己复核一遍**。

## 目录

- [路径](#路径)
- [文件结构](#文件结构)
- [格式约定](#格式约定)
- [写入步骤](#写入步骤)
- [三个容易踩的点](#三个容易踩的点)

## 路径

| 侧 | 路径 |
|---|---|
| Windows | `D:\obsidian\xnote\WorkLog\Oazon\daily.md` |
| WSL（实际操作用这个） | `/mnt/d/obsidian/xnote/WorkLog/Oazon/daily.md` |

库根目录 2026-08 前叫 `xan`，现已改名 `xnote`。**库还可能再改名**——`No such file or directory` 时别猜，直接 `find /mnt/d/obsidian -maxdepth 4 -iname daily.md` 定位，并注意同名的 `WorkLog/DigiFinance/daily.md` 是另一份，别写错。

文件约 2800 行、110KB，从 2025-05 一路记到现在。**行尾是 LF，不是 CRLF**——虽然在 Windows 盘上。写入时别引入 `\r`，用 `file <target>` 确认结果仍是 `UTF-8 text` 而不是 `with CRLF line terminators`。

## 文件结构

```
---
title: daily
...
updated: 2026-08-20      ← 每次写入顺手更新
tags: []
---

## 2025

5.13
1. 分析竞品skylight calendar     ← 2025 年的老格式，编号列表，不带工时
...

8.19                              ← 现行格式
- **MOCREO Smart Server**
    - 定位客户传感器按冷冻阈值误报：改规则时串到了别的设备（1h）
...

8.20                              ← 新块插在这里
- **MOCREO V2**
    - ...

                                  ← 两个空行
---                               ← 分隔线之后是与日报无关的草稿区
（卡片 id 清单、待办 checkbox、零散笔记……）
```

**新块的落点是「最后一个日期块之后、那条 `---` 之前」**，不是文件末尾。文末那一大段是用户自己的草稿区，别碰。

老的 2025 年条目是编号列表且没有工时。**不要拿它当格式依据**，照最近几天的写。

## 格式约定

实测自 8.17–8.19 三个日期块：

| 项 | 约定 | 注意 |
|---|---|---|
| 日期头 | 裸行 `8.20`，无 bullet、无 `##` | 不是 `2026-08-20`，也不补前导零 |
| 项目行 | `- **项目名**` | 不带工时 |
| 子条目缩进 | **4 个空格** | 不是 tab。历史上有个别行混了 tab，别跟着学 |
| 工时括号 | **全角** `（0.5h）` | 有少数历史行用了半角，以全角为准 |
| 日期块之间 | 一个空行 | 最后一块与 `---` 之间是两个空行 |
| 「明日待跟进」 | **不写** | 全文件 0 处使用，只留在会话草稿里 |

项目名**优先复用文件里近期出现过的**。8 月用过的：`MOCREO V2`、`MOCREO V3`、`MOCREO Smart Server`、`SyncSign`、`http_server`、`服务器运维`、`CalendarLoop`、`FamilyCalendar`、`Zammad`、`其他`。

粒度上宁可归并不要新造：两三个条目撑不起一个大项，塞进最接近的既有项目即可。（真实反馈：一次把挂测监控单列成大项，用户要求并回 `MOCREO V3`。）

## 写入步骤

`$SP` = 会话 scratchpad，`$T` = 目标文件。

```bash
# 1. 备份
cp "$T" "$SP/daily.backup-$(date +%Y%m%d-%H%M%S).md"
cp "$T" "$SP/daily.orig.md"

# 2. 找落点：最后一个日期块的最后一行行号
grep -nE '^[0-9]+\.[0-9]+$' "$T" | tail -3   # 看最近几个日期头
grep -n '^---$' "$T" | tail -2               # 看尾部分隔线

# 3. 在 scratchpad 里拼新文件（N = 最后一条子条目的行号）
head -N "$SP/daily.orig.md" > "$SP/daily.new.md"
cat "$SP/block.md" >> "$SP/daily.new.md"     # block.md 以一个空行开头
tail -n +$((N+1)) "$SP/daily.orig.md" >> "$SP/daily.new.md"
sed -i 's/^updated: .*/updated: 2026-08-20/' "$SP/daily.new.md"

# 4. 验工时
grep -oE '（[0-9.]+h）' "$SP/block.md" | tr -d '（h）' | paste -sd+ | bc

# 5. 出 diff 给用户看 —— 到这里停下，等确认
diff -u "$SP/daily.orig.md" "$SP/daily.new.md"

# 6. 确认后才写，然后回读核对
cat "$SP/daily.new.md" > "$T"
sed -n 'N,+20p' "$T"
file "$T"
```

用 `cat >` 而不是 `mv`：目标在 `/mnt/d` 上，`mv` 会连带改掉 owner/权限。

## 三个容易踩的点

1. **别用 Edit 工具直接改这个文件。** 2700 行、大量重复的 `- **其他**` 与相似条目，`old_string` 很容易撞上多处或匹配失败。`head`/`tail` 拼接 + `diff` 是可验证的，出错也只影响 scratchpad 里的副本。

2. **`updated:` 字段历史上没被同步维护过**（曾长期停在比最后一条日期早一周的值）。顺手更新是对的，但它是独立于日报内容的一处改动，diff 里要单独点出来让用户看见。

3. **卡片链接要从 `posts.json` 捞。** `mine.txt` 里全被替换成了 `[url]`，直接照抄会写进一堆死链：

   ```bash
   grep -oE 'https://boost\.oazon\.com/kanban/board/[a-z0-9]+\?card=[a-z0-9]+' posts.json | sort -u
   ```

   只有 card id 没有 board id 时，反查一次：`grep -oE 'board/([a-z0-9]+)\?card=<cid>' posts.json`。配不上 board 的宁可不加链接，也不要猜一个板 id 拼上去。
