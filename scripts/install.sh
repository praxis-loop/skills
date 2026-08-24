#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_ROOT="$REPO_ROOT/skills"

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "需要 bash 4 或更高版本。macOS 自带的是 bash 3.2，请用 brew install bash 后重试。" >&2
  exit 1
fi

# shellcheck source=lib/picker.sh
. "$REPO_ROOT/scripts/lib/picker.sh"
# shellcheck source=lib/skill-meta.sh
. "$REPO_ROOT/scripts/lib/skill-meta.sh"

has_skill_entry() {
  [ -f "$1/SKILL.md" ] || [ -f "$1/skill.md" ]
}

list_skill_records() {
  [ -d "$SKILLS_ROOT" ] || return 0
  find "$SKILLS_ROOT" -mindepth 3 -maxdepth 3 -type d \
    | sort \
    | while IFS= read -r dir; do
        if has_skill_entry "$dir"; then
          domain_dir="$(dirname "$dir")"
          function_dir="$(dirname "$domain_dir")"
          function_name="$(basename "$function_dir")"
          domain_name="$(basename "$domain_dir")"
          skill_name="$(basename "$dir")"
          printf '%s|%s|%s|%s|%s\n' "$function_name/$domain_name/$skill_name" "$dir" "$skill_name" "$function_name" "$domain_name"
        fi
      done
}

TARGET_LABELS=(
  "Codex 用户级"
  "Claude Code 项目级"
  "Claude Code 用户级"
  "自定义目录"
)

target_dir_for_choice() {
  case "$1" in
    1) printf '%s\n' "$HOME/.agents/skills" ;;
    2) printf '%s\n' "$(pwd)/.claude/skills" ;;
    3) printf '%s\n' "$HOME/.claude/skills" ;;
    4)
      local custom_dir
      read -r -p "请输入目标目录绝对路径或相对路径: " custom_dir
      if [ -z "${custom_dir:-}" ]; then
        echo "自定义目录不能为空" >&2
        exit 1
      fi
      case "$custom_dir" in
        ~*) printf '%s\n' "${custom_dir/#\~/$HOME}" ;;
        /*) printf '%s\n' "$custom_dir" ;;
        *) printf '%s\n' "$(pwd)/$custom_dir" ;;
      esac
      ;;
    *)
      echo "无效选择" >&2
      exit 1
      ;;
  esac
}

target_note() {
  case "$1" in
    1) printf '%s\n\n%s\n' "~/.agents/skills" "装到当前用户的 Codex skill 目录，所有项目共享。" ;;
    2) printf '%s\n\n%s\n' "./.claude/skills" "只对当前这个项目生效，适合跟着仓库一起走。" ;;
    3) printf '%s\n\n%s\n' "~/.claude/skills" "装到当前用户的 Claude Code skill 目录，所有项目共享。" ;;
    4) printf '%s\n\n%s\n' "手动输入路径" "确认后再输入目标目录，支持绝对路径、相对路径和 ~ 开头。" ;;
  esac
}

prompt_target_dir_tui() {
  TUI_ITEMS=()
  TUI_NOTES=()
  local i
  for i in 0 1 2 3; do
    TUI_ITEMS+=("${TARGET_LABELS[$i]}")
    TUI_NOTES+=("$(target_note "$((i + 1))")")
  done
  if ! tui_select single "选择安装目标"; then
    echo "已取消。" >&2
    exit 1
  fi
  target_dir_for_choice "$((TUI_RESULT[0] + 1))"
}

prompt_target_dir_plain() {
  echo >&2
  echo "请选择安装目标：" >&2
  echo "  1) Codex 用户级: ~/.agents/skills" >&2
  echo "  2) Claude Code 项目级: ./.claude/skills" >&2
  echo "  3) Claude Code 用户级: ~/.claude/skills" >&2
  echo "  4) 自定义目录" >&2
  local target_choice
  read -r -p "输入编号 [1-4]: " target_choice
  target_dir_for_choice "${target_choice:-}"
}

install_link() {
  local display="$1"
  local source_dir="$2"
  local skill_name="$3"
  local target_dir="$4"
  local link_path="$target_dir/$skill_name"

  if [ ! -d "$source_dir" ] || ! has_skill_entry "$source_dir"; then
    echo "跳过：$display 不是有效 skill 目录"
    return
  fi

  mkdir -p "$target_dir"

  if [ -L "$link_path" ]; then
    ln -sfn "$source_dir" "$link_path"
    echo "已更新软链接：$link_path -> $source_dir"
    return
  fi

  if [ -e "$link_path" ]; then
    echo "目标已存在且不是软链接，跳过：$link_path"
    echo "如需覆盖，请先手动移动或删除该目录。"
    return
  fi

  ln -s "$source_dir" "$link_path"
  echo "已安装：$link_path -> $source_dir"
}

mapfile -t RECORDS < <(list_skill_records)

if [ "${#RECORDS[@]}" -eq 0 ]; then
  echo "没有发现 skill 目录。请使用 skills/<function>/<domain>/<skill-name>/SKILL.md 结构。" >&2
  exit 1
fi

load_category_meta "$REPO_ROOT/docs/CATEGORIES.md"

declare -a SUMMARIES=()
for i in "${!RECORDS[@]}"; do
  IFS='|' read -r display source_dir skill_name function_name domain_name <<< "${RECORDS[$i]}"
  SUMMARIES[i]="$(skill_summary "$skill_name" "$source_dir")"
done

declare -a SELECTED=()

if tui_supported; then
  TUI_ITEMS=()
  TUI_NOTES=()
  for i in "${!RECORDS[@]}"; do
    IFS='|' read -r display source_dir skill_name function_name domain_name <<< "${RECORDS[$i]}"
    TUI_ITEMS+=("$display")
    TUI_NOTES+=("$(printf '%s\n%s · %s\n\n%s\n' \
      "$skill_name" \
      "$domain_name" \
      "$(skill_origin "$skill_name")" \
      "${SUMMARIES[$i]}")")
  done

  if ! tui_select multi "选择要安装的 skill"; then
    echo "已取消。" >&2
    exit 1
  fi

  for i in "${TUI_RESULT[@]}"; do
    SELECTED+=("${RECORDS[$i]}")
  done

  TARGET_DIR="$(prompt_target_dir_tui)"
else
  echo "发现以下 skill："
  for i in "${!RECORDS[@]}"; do
    IFS='|' read -r display source_dir skill_name function_name domain_name <<< "${RECORDS[$i]}"
    printf "  %d) %s\n" "$((i + 1))" "$display"
    printf "       %s\n" "${SUMMARIES[$i]}"
  done
  echo "  a) 全部安装"

  read -r -p "请选择要安装的 skill（例如 1,3 或 a）: " selection

  TARGET_DIR="$(prompt_target_dir_plain)"

  if [ "$selection" = "a" ] || [ "$selection" = "A" ]; then
    SELECTED=("${RECORDS[@]}")
  else
    IFS=',' read -ra PARTS <<< "$selection"
    for part in "${PARTS[@]}"; do
      part="${part//[[:space:]]/}"
      if ! [[ "$part" =~ ^[0-9]+$ ]]; then
        echo "无效选择：$part" >&2
        exit 1
      fi
      idx=$((part - 1))
      if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#RECORDS[@]}" ]; then
        echo "选择超出范围：$part" >&2
        exit 1
      fi
      SELECTED+=("${RECORDS[$idx]}")
    done
  fi
fi

echo
echo "安装目标：$TARGET_DIR"
for record in "${SELECTED[@]}"; do
  IFS='|' read -r display source_dir skill_name function_name domain_name <<< "$record"
  install_link "$display" "$source_dir" "$skill_name" "$TARGET_DIR"
done

echo
echo "完成。若 CLI 没有立即识别新 skill，请重启对应 CLI。"
