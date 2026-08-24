#!/usr/bin/env bash
# 交互式选择器：方向键移动，空格勾选，右侧面板显示当前项的旁白。
#
# 由 scripts/install.sh source。只在 TTY 下使用，非 TTY 时调用方回退到编号输入。
#
# 宽度说明：脚本可能运行在 C locale 下，此时 bash 的 ${#s} 数的是字节，
# 中文会被算成 3 列。所以所有宽度计算和折行都交给下面的 awk，在 LC_ALL=C
# 下按字节手工解码 UTF-8，再按东亚宽度判定 1 列还是 2 列。

_TUI_AWK='
function init(  i) { for (i = 0; i < 256; i++) ORD[sprintf("%c", i)] = i }

function cw(cp) {
  if ((cp >= 4352   && cp <= 4447)   ||
      (cp >= 11904  && cp <= 12350)  ||
      (cp >= 12353  && cp <= 13311)  ||
      (cp >= 13312  && cp <= 19903)  ||
      (cp >= 19968  && cp <= 40959)  ||
      (cp >= 40960  && cp <= 42127)  ||
      (cp >= 44032  && cp <= 55203)  ||
      (cp >= 63744  && cp <= 64255)  ||
      (cp >= 65072  && cp <= 65135)  ||
      (cp >= 65280  && cp <= 65376)  ||
      (cp >= 65504  && cp <= 65510)  ||
      (cp >= 127744 && cp <= 129791) ||
      (cp >= 131072)) return 2
  return 1
}

function decode(s, i,   b) {
  b = ORD[substr(s, i, 1)]
  if (b < 128) { CP = b; CLEN = 1 }
  else if (b < 224) {
    CP = (b - 192) * 64 + ORD[substr(s, i + 1, 1)] - 128
    CLEN = 2
  }
  else if (b < 240) {
    CP = (b - 224) * 4096 + (ORD[substr(s, i + 1, 1)] - 128) * 64 + ORD[substr(s, i + 2, 1)] - 128
    CLEN = 3
  }
  else {
    CP = (b - 240) * 262144 + (ORD[substr(s, i + 1, 1)] - 128) * 4096 + (ORD[substr(s, i + 2, 1)] - 128) * 64 + ORD[substr(s, i + 3, 1)] - 128
    CLEN = 4
  }
  if (CLEN < 1) CLEN = 1
}

function strwidth(s,   i, n, w) {
  n = length(s); i = 1; w = 0
  while (i <= n) { decode(s, i); w += cw(CP); i += CLEN }
  return w
}

# 按显示宽度截断，末尾补 ".."
function truncate(s, w,   i, n, out, lw, keep) {
  if (strwidth(s) <= w) return s
  keep = w - 2
  if (keep < 1) return substr(s, 1, w)
  n = length(s); i = 1; out = ""; lw = 0
  while (i <= n) {
    decode(s, i)
    if (lw + cw(CP) > keep) break
    out = out substr(s, i, CLEN); lw += cw(CP); i += CLEN
  }
  return out ".."
}

# 把一段文本切成 token：连续的窄字符算一个词，每个宽字符自成一个 token。
# TS[k] 记录该 token 前面在原文里是否有空白，折行时用来决定要不要补空格。
function tokenize(s,   i, n, ch, width, tok, tokw, startsp, pendsp) {
  split("", T); split("", TW); split("", TS)
  NT = 0; tok = ""; tokw = 0; startsp = 0; pendsp = 0
  n = length(s); i = 1
  while (i <= n) {
    decode(s, i)
    ch = substr(s, i, CLEN)
    width = cw(CP)
    i += CLEN
    if (ch == " " || ch == "\t") {
      if (tok != "") { NT++; T[NT] = tok; TW[NT] = tokw; TS[NT] = startsp; tok = ""; tokw = 0 }
      pendsp = 1
      continue
    }
    if (width == 2) {
      if (tok != "") { NT++; T[NT] = tok; TW[NT] = tokw; TS[NT] = startsp; tok = ""; tokw = 0 }
      NT++; T[NT] = ch; TW[NT] = 2; TS[NT] = pendsp; pendsp = 0
      continue
    }
    if (tok == "") { startsp = pendsp; pendsp = 0 }
    tok = tok ch; tokw += width
  }
  if (tok != "") { NT++; T[NT] = tok; TW[NT] = tokw; TS[NT] = startsp }
}

# 超过整行宽度的单个 token（长 URL、长路径）直接硬切。
function hardsplit(t, w, pfx,   i, n, ch, line, lw) {
  n = length(t); i = 1; line = ""; lw = 0
  while (i <= n) {
    decode(t, i)
    ch = substr(t, i, CLEN)
    if (lw + cw(CP) > w) { print pfx "\t" line; line = ""; lw = 0 }
    line = line ch; lw += cw(CP)
    i += CLEN
  }
  return line
}

function wrap(s, w, pfx,   k, line, lw, need) {
  if (w < 4) w = 4
  tokenize(s)
  line = ""; lw = 0
  for (k = 1; k <= NT; k++) {
    need = TW[k] + ((lw > 0 && TS[k]) ? 1 : 0)
    if (lw > 0 && lw + need > w) { print pfx "\t" line; line = ""; lw = 0 }
    if (lw > 0 && TS[k]) { line = line " "; lw++ }
    if (TW[k] > w) {
      if (line != "") { print pfx "\t" line; line = ""; lw = 0 }
      line = hardsplit(T[k], w, pfx)
      lw = strwidth(line)
      continue
    }
    line = line T[k]; lw += TW[k]
  }
  print pfx "\t" line
}

BEGIN { FS = "\t"; init() }
{
  if (MODE == "width") { print $1 "\t" strwidth($2) }
  else if (MODE == "trunc") { print $1 "\t" truncate($2, W + 0) }
  else { wrap($2, W + 0, $1) }
}
'

# tui_supported —— 判断当前环境能不能画交互界面
tui_supported() {
  [ -z "${NO_TUI:-}" ] || return 1
  [ -t 0 ] || return 1
  [ -t 1 ] || return 1
  case "${TERM:-dumb}" in
    dumb | "") return 1 ;;
  esac
  return 0
}

# tui_widths —— 输入 "序号<TAB>文本"，输出 "序号<TAB>显示宽度"
tui_widths() {
  LC_ALL=C awk -v MODE=width "$_TUI_AWK"
}

# tui_wrap <宽度> —— 输入 "序号<TAB>文本"，输出多行 "序号<TAB>折行后的内容"
tui_wrap() {
  LC_ALL=C awk -v MODE=wrap -v W="$1" "$_TUI_AWK"
}

# tui_trunc <宽度> —— 输入 "序号<TAB>文本"，输出 "序号<TAB>截断后的内容"
tui_trunc() {
  LC_ALL=C awk -v MODE=trunc -v W="$1" "$_TUI_AWK"
}

_tui_term_cols() {
  local c
  c="$(tput cols 2>/dev/null || true)"
  [[ "$c" =~ ^[0-9]+$ ]] || c="${COLUMNS:-80}"
  [[ "$c" =~ ^[0-9]+$ ]] || c=80
  printf '%s\n' "$c"
}

_tui_term_lines() {
  local l
  l="$(tput lines 2>/dev/null || true)"
  [[ "$l" =~ ^[0-9]+$ ]] || l="${LINES:-24}"
  [[ "$l" =~ ^[0-9]+$ ]] || l=24
  printf '%s\n' "$l"
}

_tui_restore() {
  printf '\033[?25h\033[?1049l' >&2
}

# 读一个按键，方向键这类转义序列一次读全
_tui_readkey() {
  local key rest
  IFS= read -rsn1 key || return 1
  if [ "$key" = $'\033' ]; then
    rest=""
    IFS= read -rsn2 -t 0.05 rest || true
    key="$key$rest"
  fi
  printf '%s' "$key"
}

# 测量 labels[] 的显示宽度，结果写回 widths[] 和 maxw（由 tui_select 声明）
_tui_measure_labels() {
  local i idx w
  maxw=0
  while IFS=$'\t' read -r idx w; do
    widths[idx]="$w"
    [ "$w" -gt "$maxw" ] && maxw="$w"
  done < <(
    for i in "${!labels[@]}"; do
      printf '%s\t%s\n' "$i" "${labels[$i]}"
    done | tui_widths
  )
}

# tui_select <mode> <title>
#
#   mode  multi | single
#   输入   TUI_ITEMS[]      每项的标签
#          TUI_NOTES[]      每项的旁白，用 \n 分段，段内自动折行
#          TUI_PRECHECKED[] 可选，1 表示进入时已勾选
#          TUI_ALERT[]      可选，1 表示该项标黄提醒
#          TUI_DIFF         可选，multi 下设为 1 进入差异模式：
#                           勾选框直接代表目标状态，用 [x]/[+]/[-]/[ ]
#                           显示「保持/新增/移除/不装」，并统计增删数量
#   输出   TUI_RESULT[]     确认时处于勾选状态的下标
#
# 返回 1 表示用户取消。调用方每次调用前应显式设置上面这些输入数组。
tui_select() {
  local mode="$1" title="$2"
  local count="${#TUI_ITEMS[@]}"
  [ "$count" -gt 0 ] || return 1

  local dim=$'\033[2m' bold=$'\033[1m' cyan=$'\033[36m' green=$'\033[32m'
  local yellow=$'\033[33m' red=$'\033[31m' reset=$'\033[0m'
  if [ -n "${NO_COLOR:-}" ]; then
    dim=""; bold=""; cyan=""; green=""; yellow=""; red=""; reset=""
  fi

  local cols rows
  cols="$(_tui_term_cols)"
  rows="$(_tui_term_lines)"
  [ "$cols" -gt 110 ] && cols=110

  local margin=2 gutter=3 min_note=30
  local prefix_w=6
  [ "$mode" = "single" ] && prefix_w=2

  local side=1
  local avail=$((cols - margin - prefix_w - gutter - min_note))
  if [ "$avail" -lt 14 ]; then
    # 终端实在太窄，旁白改成放在列表下方
    side=0
    avail=$((cols - margin - prefix_w))
  fi
  [ "$avail" -lt 8 ] && avail=8

  # 左栏放不下完整路径时逐级退化：function/domain/skill -> function/skill
  # -> skill -> 硬截断。完整路径右侧旁白里始终有，所以缩短是安全的。
  local -a labels=() widths=()
  local i maxw=0
  for i in "${!TUI_ITEMS[@]}"; do labels[i]="${TUI_ITEMS[$i]}"; done
  _tui_measure_labels

  local step
  for step in 1 2; do
    [ "$maxw" -le "$avail" ] && break
    for i in "${!labels[@]}"; do
      [ "${widths[$i]}" -le "$avail" ] && continue
      case "$step" in
        1) [[ "${labels[$i]}" == */*/* ]] && labels[i]="${labels[$i]%%/*}/${labels[$i]##*/}" ;;
        2) [[ "${labels[$i]}" == */* ]] && labels[i]="${labels[$i]##*/}" ;;
      esac
    done
    _tui_measure_labels
  done

  if [ "$maxw" -gt "$avail" ]; then
    while IFS=$'\t' read -r i step; do
      labels[i]="$step"
    done < <(
      for i in "${!labels[@]}"; do
        printf '%s\t%s\n' "$i" "${labels[$i]}"
      done | tui_trunc "$avail"
    )
    _tui_measure_labels
  fi

  local left=$((maxw + prefix_w))
  local note_w
  if [ "$side" -eq 1 ]; then
    note_w=$((cols - margin - left - gutter))
    [ "$note_w" -lt 16 ] && note_w=16
  else
    note_w=$((cols - margin))
    [ "$note_w" -lt 16 ] && note_w=16
  fi

  # 预折行：渲染时只做纯字符串拼接，避免每次按键都调 awk
  local -a note_lines=() note_off=() note_cnt=()
  local flat=0
  for i in "${!TUI_ITEMS[@]}"; do
    note_off[i]="$flat"
    local n=0 line
    while IFS=$'\t' read -r idx line; do
      note_lines[flat]="$line"
      flat=$((flat + 1))
      n=$((n + 1))
    done < <(printf '%s\n' "${TUI_NOTES[$i]}" | awk -v i="$i" 'BEGIN{OFS="\t"} {print i, $0}' | tui_wrap "$note_w")
    note_cnt[i]="$n"
  done

  # base[] 是进入时的初始状态，用来算出「新增」和「移除」的差异
  local -a checked=() base=()
  for i in "${!TUI_ITEMS[@]}"; do
    base[i]="${TUI_PRECHECKED[$i]:-0}"
    checked[i]="${base[$i]}"
  done

  local diffmode=0
  [ "$mode" = "multi" ] && [ "${TUI_DIFF:-0}" -eq 1 ] && diffmode=1

  local hint
  if [ "$diffmode" -eq 1 ]; then
    hint="↑↓/jk 移动   空格 切换   a 全选   n 清空   r 还原   回车 应用   q 取消"
  elif [ "$mode" = "multi" ]; then
    hint="↑↓/jk 移动   空格 勾选   a 全选   n 清空   回车 确认   q 取消"
  else
    hint="↑↓/jk 移动   回车 选择   q 取消"
  fi

  # 标题里常带着目标路径，窄终端下会撑出屏幕，按显示宽度截断
  local disp_title disp_hint
  disp_title="$(printf '0\t%s\n' "$title" | tui_trunc $((cols - margin)) | cut -f2-)"
  disp_hint="$(printf '0\t%s\n' "$hint" | tui_trunc $((cols - margin)) | cut -f2-)"

  local head_lines=4
  local foot_lines=2
  [ "$diffmode" -eq 1 ] && foot_lines=3
  local view=$((rows - head_lines - foot_lines))
  [ "$view" -lt 3 ] && view=3
  [ "$view" -gt "$count" ] && view="$count"

  local cursor=0 top=0
  trap '_tui_restore' EXIT INT TERM
  printf '\033[?1049h\033[?25l' >&2

  local key frame
  while true; do
    [ "$cursor" -lt "$top" ] && top="$cursor"
    [ "$cursor" -ge $((top + view)) ] && top=$((cursor - view + 1))

    local cur_off="${note_off[$cursor]}" cur_cnt="${note_cnt[$cursor]}"
    local body=$view
    if [ "$side" -eq 1 ] && [ "$cur_cnt" -gt "$body" ]; then
      body="$cur_cnt"
      [ "$body" -gt $((rows - head_lines - foot_lines)) ] && body=$((rows - head_lines - foot_lines))
    fi

    frame=$'\033[H'
    frame+="  ${bold}${disp_title}${reset}"$'\033[K\n'
    frame+="  ${dim}${disp_hint}${reset}"$'\033[K\n'
    frame+=$'\033[K\n'

    local r
    for ((r = 0; r < body; r++)); do
      local li=$((top + r))
      local lcell=""
      if [ "$li" -lt "$count" ] && [ "$r" -lt "$view" ]; then
        local point=" " mark="" mcolor="$dim"
        [ "$li" -eq "$cursor" ] && point="❯"
        if [ "$diffmode" -eq 1 ]; then
          if [ "${checked[$li]}" -eq 1 ] && [ "${base[$li]}" -eq 1 ]; then
            mark="[x] "; mcolor="$green"
          elif [ "${checked[$li]}" -eq 1 ]; then
            mark="[+] "; mcolor="$yellow"
          elif [ "${base[$li]}" -eq 1 ]; then
            mark="[-] "; mcolor="$red"
          else
            mark="[ ] "; mcolor="$dim"
          fi
        elif [ "$mode" = "multi" ]; then
          if [ "${checked[$li]}" -eq 1 ]; then mark="[x] "; mcolor="$green"; else mark="[ ] "; mcolor="$dim"; fi
        fi
        local pad=$((left - prefix_w - widths[li]))
        [ "$pad" -lt 0 ] && pad=0
        local label="${labels[$li]}"
        local lcolor="" lend=""
        if [ "${TUI_ALERT[$li]:-0}" -eq 1 ]; then lcolor="$yellow"; lend="$reset"; fi
        local spaces=""
        [ "$pad" -gt 0 ] && printf -v spaces '%*s' "$pad" ""
        if [ "$li" -eq "$cursor" ]; then
          lcell="${cyan}${point} ${mark}${label}${reset}${spaces}"
        else
          lcell="${point} ${mcolor}${mark}${reset}${lcolor}${label}${lend}${spaces}"
        fi
      else
        printf -v lcell '%*s' "$left" ""
      fi

      if [ "$side" -eq 1 ]; then
        local ncell=""
        if [ "$r" -lt "$cur_cnt" ]; then
          local nl="${note_lines[$((cur_off + r))]}"
          case "$r" in
            0) ncell="${bold}${nl}${reset}" ;;
            1) ncell="${dim}${nl}${reset}" ;;
            *) ncell="$nl" ;;
          esac
        fi
        frame+="  ${lcell}${dim} │ ${reset}${ncell}"$'\033[K\n'
      else
        frame+="  ${lcell}"$'\033[K\n'
      fi
    done

    if [ "$side" -eq 0 ]; then
      frame+=$'\033[K\n'
      for ((r = 0; r < cur_cnt; r++)); do
        local nl="${note_lines[$((cur_off + r))]}"
        case "$r" in
          0) frame+="  ${bold}${nl}${reset}"$'\033[K\n' ;;
          1) frame+="  ${dim}${nl}${reset}"$'\033[K\n' ;;
          *) frame+="  ${nl}"$'\033[K\n' ;;
        esac
      done
    fi

    frame+=$'\033[K\n'
    if [ "$mode" = "multi" ]; then
      local picked=0 added=0 removed=0
      for i in "${!checked[@]}"; do
        [ "${checked[$i]}" -eq 1 ] && picked=$((picked + 1))
        if [ "${checked[$i]}" -eq 1 ] && [ "${base[$i]}" -eq 0 ]; then added=$((added + 1)); fi
        if [ "${checked[$i]}" -eq 0 ] && [ "${base[$i]}" -eq 1 ]; then removed=$((removed + 1)); fi
      done
      if [ "$diffmode" -eq 1 ]; then
        frame+="  ${dim}已选 ${picked}/${count}   将新增 ${yellow}${added}${dim} 个、移除 ${red}${removed}${dim} 个${reset}"$'\033[K\n'
        frame+="  ${green}[x]${reset}${dim} 已装   ${yellow}[+]${reset}${dim} 将新增   ${red}[-]${reset}${dim} 将移除   [ ] 未装${reset}"$'\033[K\n'
      else
        frame+="  ${dim}已选 ${picked}/${count}${reset}"$'\033[K\n'
      fi
    fi
    frame+=$'\033[J'
    printf '%s' "$frame" >&2

    key="$(_tui_readkey)" || key="q"
    case "$key" in
      $'\033[A' | k) cursor=$(((cursor - 1 + count) % count)) ;;
      $'\033[B' | j) cursor=$(((cursor + 1) % count)) ;;
      $'\033[5~') cursor=$((cursor - view)); [ "$cursor" -lt 0 ] && cursor=0 ;;
      $'\033[6~') cursor=$((cursor + view)); [ "$cursor" -ge "$count" ] && cursor=$((count - 1)) ;;
      g) cursor=0 ;;
      G) cursor=$((count - 1)) ;;
      " ")
        if [ "$mode" = "multi" ]; then
          if [ "${checked[$cursor]}" -eq 1 ]; then checked[cursor]=0; else checked[cursor]=1; fi
        fi
        ;;
      a | A)
        if [ "$mode" = "multi" ]; then
          for i in "${!checked[@]}"; do checked[i]=1; done
        fi
        ;;
      n | N)
        if [ "$mode" = "multi" ]; then
          for i in "${!checked[@]}"; do checked[i]=0; done
        fi
        ;;
      r | R)
        if [ "$diffmode" -eq 1 ]; then
          for i in "${!checked[@]}"; do checked[i]="${base[$i]}"; done
        fi
        ;;
      "" | $'\r' | $'\n')
        TUI_RESULT=()
        if [ "$mode" = "single" ]; then
          TUI_RESULT=("$cursor")
        else
          for i in "${!checked[@]}"; do [ "${checked[$i]}" -eq 1 ] && TUI_RESULT+=("$i"); done
          # 普通多选下一个都没勾时，把光标所在项当作选中，避免空确认。
          # diff 模式下「全都不勾」是合法意图（表示全部移除），不能替用户改。
          if [ "$diffmode" -eq 0 ] && [ "${#TUI_RESULT[@]}" -eq 0 ]; then
            TUI_RESULT=("$cursor")
          fi
        fi
        _tui_restore
        trap - EXIT INT TERM
        return 0
        ;;
      q | Q | $'\033')
        _tui_restore
        trap - EXIT INT TERM
        return 1
        ;;
    esac
  done
}
