#!/usr/bin/env bash
# 读取 skill 的一句话简介，供安装器的旁白面板使用。
#
# 优先级：
#   1. docs/CATEGORIES.md「当前 Skill」表格里的「说明」列，这是仓库规范
#      要求随 skill 一起维护的人工摘要，措辞最统一。
#   2. SKILL.md frontmatter 里 description 的第一句。
#
# 不从 SKILL.md 里新增字段：lark-* 等第三方快照禁止手工修改。

declare -A SKILL_SUMMARY=()
declare -A SKILL_ORIGIN=()

# load_category_meta <CATEGORIES.md 路径>
load_category_meta() {
  local doc="$1"
  [ -f "$doc" ] || return 0
  local name origin summary
  while IFS=$'\t' read -r name origin summary; do
    [ -n "$name" ] || continue
    SKILL_SUMMARY["$name"]="$summary"
    SKILL_ORIGIN["$name"]="$origin"
  done < <(
    awk -F'|' '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      function plain(s) {
        s = trim(s)
        gsub(/`/, "", s)
        return trim(s)
      }
      /^##[[:space:]]/ { in_table = ($0 ~ /当前 Skill/); next }
      !in_table { next }
      NF >= 5 && $1 == "" {
        name = plain($2)
        if (name == "" || name == "Skill" || name ~ /^-+$/) next
        print name "\t" plain($4) "\t" plain($5)
      }
    ' "$doc"
  )
}

# frontmatter_description <skill 目录>
frontmatter_description() {
  local dir="$1" file=""
  if [ -f "$dir/SKILL.md" ]; then
    file="$dir/SKILL.md"
  elif [ -f "$dir/skill.md" ]; then
    file="$dir/skill.md"
  else
    return 0
  fi
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && /^---[[:space:]]*$/ { exit }
    NR > 1 && /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
  ' "$file"
}

# skill_summary <skill 名> <skill 目录>
skill_summary() {
  local name="$1" dir="$2" text=""

  if [ -n "${SKILL_SUMMARY[$name]:-}" ]; then
    printf '%s\n' "${SKILL_SUMMARY[$name]}"
    return 0
  fi

  text="$(frontmatter_description "$dir")"
  text="${text#\"}"
  text="${text%\"}"
  text="${text#\'}"
  text="${text%\'}"

  # 取第一句：中文句号优先，其次英文句号加空格
  local first="${text%%。*}"
  if [ "$first" = "$text" ]; then
    first="${text%%. *}"
  fi
  first="${first//\`/}"
  first="${first#"${first%%[![:space:]]*}"}"
  first="${first%"${first##*[![:space:]]}"}"

  if [ -z "$first" ]; then
    printf '%s\n' "（未登记简介，见 SKILL.md）"
  else
    printf '%s\n' "$first"
  fi
}

# skill_origin <skill 名>
skill_origin() {
  printf '%s\n' "${SKILL_ORIGIN[$1]:-未登记}"
}
