#!/usr/bin/env python3
"""从 Mattermost 抓取某一天的会话内容，供日报整理使用。

走 opencli 的浏览器桥接（`opencli browser <session> eval`），在页面上下文里直接调
Mattermost REST API，复用浏览器已有的登录态，因此不需要额外的 token。

依赖：
  - opencli（在 PATH 中，且 `opencli doctor` 显示 extension 已连接）
  - python3 标准库

用法：
  python3 fetch_mm_day.py --out ./mmday
  python3 fetch_mm_day.py --date 2026-08-12 --out ./mmday
  python3 fetch_mm_day.py --date 2026-08-12 --me loki --out ./mmday

输出（写入 --out 目录）：
  meta.json      本次抓取的参数、频道清单、统计
  posts.json     全量消息（按频道分组，结构化）
  summary.txt    每频道条数与时间区间、每人发言数
  mine.txt       我发的 + @我 的消息（整理个人日报优先看这个）
  ch-NN-<slug>.txt  分频道纯文本，便于逐个阅读
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_SERVER = "https://mm.oazon.com"
DEFAULT_TZ_OFFSET = 8  # Asia/Shanghai

# 机器人流程噪音，渲染纯文本时默认过滤（不影响 posts.json）
NOISE_PREFIXES = (
    "⌛",
    "🔎",
    "🧠",
    "✅ sent",
    "⏳ 当前所有会话",
)


# --------------------------------------------------------------------------- #
# opencli 调用
# --------------------------------------------------------------------------- #

def resolve_opencli_command(
    os_name: str | None = None,
    which=shutil.which,
) -> list[str]:
    """返回可由 subprocess 直接执行的 OpenCLI 命令前缀。"""
    current_os = os_name or os.name
    if current_os != "nt":
        executable = which("opencli")
        if not executable:
            raise RuntimeError("PATH 中找不到 opencli")
        return [executable]

    node = which("node")
    shim = which("opencli.cmd") or which("opencli")
    if not node or not shim:
        raise RuntimeError("Windows 下找不到 node 或 opencli.cmd")

    entry = (
        Path(shim).resolve().parent
        / "node_modules"
        / "@jackwener"
        / "opencli"
        / "dist"
        / "src"
        / "main.js"
    )
    if not entry.is_file():
        raise RuntimeError(f"找不到 OpenCLI Node 入口：{entry}")
    return [node, str(entry)]


def run_opencli(
    args: list[str],
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    """以 UTF-8 文本模式运行 OpenCLI，避免 Windows 默认代码页误解码。"""
    return subprocess.run(
        [*resolve_opencli_command(), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
    )

def extract_payload(stdout: str) -> str:
    """opencli 会在 stdout 里混入 node 的实验性警告，取 JSON 载荷。

    载荷不保证是单行：消息正文里的换行会被原样带出来，只取首行会把 JSON
    从中间截断（报 Unterminated string）。所以从第一行 JSON 起把余下的行
    全部接回去。
    """
    lines = stdout.splitlines()
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("{") or stripped.startswith("["):
            return "\n".join([stripped, *lines[idx + 1:]])
    raise RuntimeError(
        "opencli 返回中找不到 JSON 载荷；原始输出：\n" + stdout[:2000]
    )


def run_eval(js: str, session: str, timeout: int) -> object:
    proc = run_opencli(["browser", session, "eval", js], timeout)
    if proc.returncode != 0:
        raise RuntimeError(
            f"opencli browser eval 失败（exit {proc.returncode}）：\n"
            f"{proc.stderr[:2000]}\n{proc.stdout[:2000]}"
        )
    # strict=False：消息正文里的裸控制字符（换行、制表）会让严格模式直接报
    # Invalid control character，这些字符对归纳无害，容忍即可。
    return json.loads(extract_payload(proc.stdout), strict=False)


def open_site(server: str, session: str, timeout: int, window: str) -> None:
    proc = run_opencli(
        ["browser", session, "open", server, "--window", window], timeout
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"打开 {server} 失败（exit {proc.returncode}）：\n{proc.stderr[:2000]}"
        )


# --------------------------------------------------------------------------- #
# 时间边界
# --------------------------------------------------------------------------- #

def day_bounds_ms(date_str: str | None, tz_offset: int) -> tuple[int, int, str]:
    """返回 (since_ms, until_ms, date_str)，按 tz_offset 指定的时区算自然日。

    这里必须显式指定时区：宿主机系统 TZ 未必是 Asia/Shanghai，
    用 `date -d "YYYY-MM-DD 00:00:00" +%s` 之类的写法会整体偏移若干小时，
    直接导致抓到的不是当天的内容。
    """
    tz = timezone(timedelta(hours=tz_offset))
    if date_str:
        day = datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=tz)
    else:
        day = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
    start = day.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    return (
        int(start.timestamp() * 1000),
        int(end.timestamp() * 1000),
        start.strftime("%Y-%m-%d"),
    )


def fmt_time(ms: int, tz_offset: int) -> str:
    tz = timezone(timedelta(hours=tz_offset))
    return datetime.fromtimestamp(ms / 1000, tz).strftime("%H:%M")


# --------------------------------------------------------------------------- #
# 抓取
# --------------------------------------------------------------------------- #

JS_CHANNELS = r"""
(async()=>{
  const H={headers:{"X-Requested-With":"XMLHttpRequest"}};
  const g=async u=>(await fetch(u,H)).json();
  const me=await g("/api/v4/users/me");
  const teams=await g("/api/v4/users/me/teams");
  const seen={},out=[];
  for(const t of teams){
    const chs=await g(`/api/v4/users/${me.id}/teams/${t.id}/channels`);
    for(const c of chs){
      if(seen[c.id])continue; seen[c.id]=1;
      let disp=c.display_name;
      if(c.type==="D"&&!disp){
        const other=c.name.split("__").find(x=>x!==me.id)||"";
        try{const u=await g(`/api/v4/users/${other}`);disp="DM:"+(u.username||other);}
        catch(e){disp="DM:"+other;}
      }
      if(c.type==="G"&&!disp)disp="GroupDM:"+c.id.slice(0,8);
      out.push({id:c.id,name:c.name,display:disp,type:c.type,team:t.display_name,last:c.last_post_at});
    }
  }
  return JSON.stringify({me:{id:me.id,username:me.username,email:me.email},
                         teams:teams.map(t=>t.display_name),channels:out});
})()
"""

JS_POSTS = r"""
(async()=>{
  const H={headers:{"X-Requested-With":"XMLHttpRequest"}};
  const g=async u=>(await fetch(u,H)).json();
  const SINCE=__SINCE__, UNTIL=__UNTIL__, MAXPAGES=__MAXPAGES__;
  const CIDS=__CIDS__;
  const uc={};
  const un=async id=>{
    if(!(id in uc)){
      try{const u=await g(`/api/v4/users/${id}`);uc[id]=u.username||id;}
      catch(e){uc[id]=id;}
    }
    return uc[id];
  };
  const res={};
  for(const cid of CIDS){
    const all={}; let page=0, done=false;
    // 两个坑：
    // 1) /posts 带 since 时结果会被 per_page 截断，所以一律用 page 翻页。
    // 2) 终止条件只能看 d.order（本页真实内容）。d.posts 会把本页回复所属的
    //    旧 thread 根帖一起塞进来，用它算 oldest 会在第 0 页就误判到底。
    while(!done&&page<MAXPAGES){
      const d=await g(`/api/v4/channels/${cid}/posts?page=${page}&per_page=200`);
      const order=d.order||[]; const bag=d.posts||{};
      if(!Object.keys(bag).length)break;
      for(const k in bag)all[k]=bag[k];
      const pageTimes=order.map(id=>bag[id]).filter(Boolean).map(p=>p.create_at);
      if(!pageTimes.length||Math.min(...pageTimes)<SINCE||order.length<200)done=true;
      page++;
    }
    const posts=Object.values(all)
      .filter(p=>p.create_at>=SINCE&&p.create_at<UNTIL&&!p.delete_at)
      .sort((a,b)=>a.create_at-b.create_at);
    const items=[];
    for(const p of posts){
      items.push({
        id:p.id, t:p.create_at, u:await un(p.user_id), type:p.type||"",
        root:p.root_id||"", msg:p.message||"",
        att:(p.props&&p.props.attachments)
            ? p.props.attachments.map(a=>[a.title,a.text].filter(Boolean).join(" | ")).join(" ~~ ")
            : ""
      });
    }
    res[cid]=items;
  }
  return JSON.stringify(res);
})()
"""


def build_posts_js(cids: list[str], since: int, until: int, maxpages: int) -> str:
    return (
        JS_POSTS.replace("__SINCE__", str(since))
        .replace("__UNTIL__", str(until))
        .replace("__MAXPAGES__", str(maxpages))
        .replace("__CIDS__", json.dumps(cids))
    )


# --------------------------------------------------------------------------- #
# 渲染
# --------------------------------------------------------------------------- #

def slugify(text: str, limit: int = 24) -> str:
    slug = re.sub(r"[^0-9A-Za-z一-鿿]+", "-", text).strip("-")
    return (slug[:limit] or "channel")


def clean_message(post: dict, truncate: int, strip_urls: bool) -> str:
    body = (post.get("msg") or "").strip()
    if post.get("att"):
        body += " ||ATT|| " + post["att"]
    body = re.sub(r"\n+", " / ", body)
    if strip_urls:
        body = re.sub(r"https?://\S+", "[url]", body)
    body = re.sub(r"\s+", " ", body).strip()
    if truncate and len(body) > truncate:
        body = body[:truncate] + "…"
    return body


def render_channel(channel: dict, posts: list[dict], tz_offset: int,
                   truncate: int, strip_urls: bool, keep_noise: bool) -> str:
    lines = [f"===== #{channel['display']} ({len(posts)} 条) ====="]
    for post in posts:
        raw = (post.get("msg") or "").strip()
        if not keep_noise and raw.startswith(NOISE_PREFIXES):
            continue
        body = clean_message(post, truncate, strip_urls)
        mark = " R" if post.get("root") else ""
        lines.append(f"[{fmt_time(post['t'], tz_offset)}] {post['u']}{mark}: {body}")
    return "\n".join(lines) + "\n"


def pick_mine(posts: list[dict], me: str, with_threads: bool) -> list[dict]:
    """我发的 + @我 的消息；with_threads 时补上同一 thread 的其余消息。

    补 thread 很重要：日报里最有信息量的往往是 bot 对我提问的那条回答，
    它不一定 @ 我，只是挂在我发起或参与的 thread 下。
    """
    mention = f"@{me}"

    def direct(post: dict) -> bool:
        return (
            post["u"] == me
            or mention in (post.get("msg") or "")
            or mention in (post.get("att") or "")
        )

    hits = [p for p in posts if direct(p)]
    if not with_threads:
        return hits

    threads = {p.get("root") or p["id"] for p in hits}
    return [p for p in posts if direct(p) or (p.get("root") or p["id"]) in threads]


def render_mine(channels: list[dict], by_channel: dict, me: str,
                tz_offset: int, truncate: int, strip_urls: bool,
                with_threads: bool = True) -> str:
    lines = [f"===== 我发的 + @{me} 的消息" + ("（含所在 thread）" if with_threads else "") + " ====="]
    total = 0
    for channel in channels:
        posts = by_channel.get(channel["id"], [])
        hits = pick_mine(posts, me, with_threads)
        if not hits:
            continue
        lines.append("")
        lines.append(f"--- #{channel['display']} ({len(hits)} 条) ---")
        for post in hits:
            who = "我" if post["u"] == me else post["u"]
            body = clean_message(post, truncate, strip_urls)
            lines.append(f"[{fmt_time(post['t'], tz_offset)}] {who}: {body}")
            total += 1
    lines.insert(1, f"合计 {total} 条")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description="抓取 Mattermost 某一天的会话内容")
    ap.add_argument("--out", required=True, help="输出目录")
    ap.add_argument("--date", help="YYYY-MM-DD，默认按 --tz-offset 的今天")
    ap.add_argument("--server", default=DEFAULT_SERVER)
    ap.add_argument("--session", default="mm", help="opencli browser 会话名")
    ap.add_argument("--me", help="覆盖当前登录用户名（默认取 users/me）")
    ap.add_argument("--tz-offset", type=int, default=DEFAULT_TZ_OFFSET,
                    help="日界线时区偏移小时数，默认 8（Asia/Shanghai）")
    ap.add_argument("--batch", type=int, default=6, help="每次 eval 抓多少个频道")
    ap.add_argument("--maxpages", type=int, default=15, help="单频道最多翻多少页")
    ap.add_argument("--truncate", type=int, default=260,
                    help="纯文本渲染时单条截断长度，0 表示不截断")
    ap.add_argument("--timeout", type=int, default=300, help="单次 eval 超时秒数")
    ap.add_argument("--window", default="background", choices=["background", "foreground"])
    ap.add_argument("--keep-urls", action="store_true", help="纯文本里保留完整 URL")
    ap.add_argument("--keep-noise", action="store_true", help="不过滤 bot 流程噪音行")
    ap.add_argument("--no-threads", action="store_true",
                    help="mine.txt 只取我发的和 @我 的，不补 thread 上下文")
    ap.add_argument("--no-open", action="store_true", help="跳过 browser open（标签页已就绪时）")
    args = ap.parse_args()

    since, until, date_str = day_bounds_ms(args.date, args.tz_offset)
    os.makedirs(args.out, exist_ok=True)

    if not args.no_open:
        print(f"[1/4] 打开 {args.server} …", file=sys.stderr)
        open_site(args.server, args.session, args.timeout, args.window)

    print("[2/4] 读取登录态与频道清单 …", file=sys.stderr)
    info = run_eval(JS_CHANNELS, args.session, args.timeout)
    me = args.me or info["me"]["username"]
    active = [c for c in info["channels"] if (c.get("last") or 0) >= since]
    active.sort(key=lambda c: c.get("last") or 0, reverse=True)
    if not active:
        print(f"当天（{date_str}）没有任何活跃频道。", file=sys.stderr)

    print(f"      登录用户 {me}，活跃频道 {len(active)} 个", file=sys.stderr)

    print("[3/4] 抓取消息 …", file=sys.stderr)
    by_channel: dict[str, list[dict]] = {}
    for i in range(0, len(active), args.batch):
        batch = active[i:i + args.batch]
        cids = [c["id"] for c in batch]
        js = build_posts_js(cids, since, until, args.maxpages)
        by_channel.update(run_eval(js, args.session, args.timeout))
        got = sum(len(by_channel.get(c, [])) for c in cids)
        print(f"      {i + len(batch)}/{len(active)} 频道，本批 {got} 条", file=sys.stderr)

    print("[4/4] 落盘 …", file=sys.stderr)
    # last_post_at 会把只有已删除消息 / 系统消息的频道也算成活跃，这里按实抓结果收敛
    active = [c for c in active if by_channel.get(c["id"])]
    # 不同 team 下可能有同名频道，加 team 后缀避免文件名与摘要混淆
    seen_names: dict[str, int] = {}
    for channel in active:
        seen_names[channel["display"]] = seen_names.get(channel["display"], 0) + 1
    for channel in active:
        if seen_names[channel["display"]] > 1:
            channel["display"] = f"{channel['display']}[{channel['team']}]"

    total = sum(len(by_channel.get(c["id"], [])) for c in active)
    per_user: dict[str, int] = {}
    for channel in active:
        for post in by_channel.get(channel["id"], []):
            per_user[post["u"]] = per_user.get(post["u"], 0) + 1

    strip_urls = not args.keep_urls
    summary = [
        f"日期 {date_str}（UTC+{args.tz_offset}）  服务器 {args.server}  登录 {me}",
        f"活跃频道 {len(active)} 个，消息合计 {total} 条",
        "",
        "频道                                     条数  时间区间",
    ]
    for idx, channel in enumerate(active):
        posts = by_channel.get(channel["id"], [])
        span = "-"
        if posts:
            span = (f"{fmt_time(posts[0]['t'], args.tz_offset)}"
                    f"–{fmt_time(posts[-1]['t'], args.tz_offset)}")
        summary.append(f"{channel['display'][:38]:<40} {len(posts):>4}  {span}")
        name = f"ch-{idx:02d}-{slugify(channel['display'])}.txt"
        with open(os.path.join(args.out, name), "w", encoding="utf-8") as fh:
            fh.write(render_channel(channel, posts, args.tz_offset,
                                    args.truncate, strip_urls, args.keep_noise))
    summary.append("")
    summary.append("发言人排行：")
    for user, count in sorted(per_user.items(), key=lambda kv: -kv[1]):
        summary.append(f"  {user:<20} {count}")

    with open(os.path.join(args.out, "summary.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(summary) + "\n")
    with open(os.path.join(args.out, "mine.txt"), "w", encoding="utf-8") as fh:
        fh.write(render_mine(active, by_channel, me, args.tz_offset,
                             args.truncate, strip_urls,
                             with_threads=not args.no_threads))
    with open(os.path.join(args.out, "posts.json"), "w", encoding="utf-8") as fh:
        json.dump(by_channel, fh, ensure_ascii=False)
    with open(os.path.join(args.out, "meta.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "date": date_str, "tz_offset": args.tz_offset,
                "since_ms": since, "until_ms": until,
                "server": args.server, "me": me,
                "teams": info.get("teams", []),
                "channels": active, "total_posts": total,
                "per_user": per_user,
            },
            fh, ensure_ascii=False, indent=2,
        )

    print(f"完成：{total} 条 / {len(active)} 个频道 → {args.out}", file=sys.stderr)
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
