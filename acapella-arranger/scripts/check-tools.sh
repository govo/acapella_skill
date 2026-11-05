#!/usr/bin/env bash
#
# check-tools.sh —— 核对 references/commands.md 与 App 真实工具表是否一致。
#
# 为什么不"生成"文档：commands.md 里的 `> 备注` 是踩坑记录（对齐口径、take 语义、
# 降级警告），机器生成不出来。所以改成**校验**：工具表由 App 派生，文档由人维护，
# 本脚本负责告警两边对不上。
#
# 用法
#   ./check-tools.sh            # 只报告：服务端有、文档没写 / 文档写了、服务端没有
#   ./check-tools.sh --table    # 直接把最新的工具表打到 stdout（人工贴进文档用）
#
# 退出码
#   0 一致 · 1 有差异（详见输出）· 3 连不上 App
#
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DOC="$HERE/../references/commands.md"
MCP="$HERE/mcp.sh"
MODE="check"
[ "${1:-}" = "--table" ] && MODE="table"

LIVE="$("$MCP" tools 2>/dev/null)"
STATUS=$?
if [ $STATUS -ne 0 ] || [ -z "$LIVE" ]; then
  echo "check-tools.sh: 读不到 tools/list（App 没开或 AI 控制没开）" >&2
  exit 3
fi

# 只取第一列（工具名）
SERVER="$(printf '%s\n' "$LIVE" | cut -f1 | sed '/^$/d' | sort)"

if [ "$MODE" = "table" ]; then
  printf '| 工具 | 参数 |\n| --- | --- |\n'
  # 参数列由 tools/list 的 inputSchema 派生（只列名字，类型见文档说明）。
  printf '%s\n' "$LIVE" | awk -F'\t' 'NF>2 { printf "| `%s` | %s |\n", $1, ($3==""?"—":$3) }'
  exit 0
fi

[ -f "$DOC" ] || { echo "check-tools.sh: $DOC 不存在" >&2; exit 1; }

# 文档里被反引号包住的名字。带点的（track.mix）和无点的（state）都要收 ——
# 服务端两种都有，只收带点的会把 state / ping / caps / revision 全报成"文档缺"。
DOC_NAMES="$(
  grep -oE '`[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)*`' "$DOC" \
    | tr -d '`' | sort -u
)"

MISSING=0
while IFS= read -r tool; do
  [ -n "$tool" ] || continue
  printf '%s\n' "$DOC_NAMES" | grep -qx "$tool" && continue
  case "$tool" in
    debug.*) continue ;;   # 调试工具允许只在代码里出现
  esac
  echo "文档缺：$tool"
  MISSING=$((MISSING + 1))
done <<< "$SERVER"

# 反向：文档里有、服务端没有。
#
# 只认「首段是真实工具前缀」的名字（track / notes / export …）。响应字段也长成
# `offset.user`、`error.code` 这种点号形状，不设这道闸会报一堆假阳性。
PREFIXES="$(printf '%s\n' "$SERVER" | awk -F. 'NF>1 {print $1}' | sort -u)"
STALE=0
while IFS= read -r tool; do
  case "$tool" in *.*) ;; *) continue ;; esac
  prefix="${tool%%.*}"
  printf '%s\n' "$PREFIXES" | grep -qx "$prefix" || continue
  printf '%s\n' "$SERVER" | grep -qx "$tool" && continue
  echo "文档多了（服务端没有）：$tool"
  STALE=$((STALE + 1))
done <<< "$DOC_NAMES"

TOTAL="$(printf '%s\n' "$SERVER" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$MISSING" -eq 0 ] && [ "$STALE" -eq 0 ]; then
  echo "OK: 文档与 tools/list 一致（$TOTAL 个工具）"
  exit 0
fi
echo "—— 服务端 ${TOTAL} 个工具；文档缺 ${MISSING}，文档多 ${STALE}"
exit 1
