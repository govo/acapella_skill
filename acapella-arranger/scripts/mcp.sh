#!/usr/bin/env bash
#
# mcp.sh —— 跟本机 Acapella 的 MCP 服务说话的最小客户端。
#
# 为什么需要它：MCP 客户端（Claude Desktop、Cursor、Codex…）里有原生工具，
# 直接在对话里调就行；但**脚本里**没有工具调用这回事，只能自己发 JSON-RPC。
# 本脚本就是那层薄壳：POST /mcp 收发，把 `data` 摊平成 JSON 打到 stdout，
# 用法跟以前那条命令行几乎一样，只是名字换成了工具名。
#
# 用法
#   ./mcp.sh health                              # 探活：端口、版本、工具数
#   ./mcp.sh tools                               # tools/list（工具名 + 参数）
#   ./mcp.sh call state                          # 无参工具
#   ./mcp.sh call track.mix '{"track":"drums","volume":"-3dB"}'
#   ./mcp.sh call notes.replace @/tmp/bass.json  # @file = 整个 arguments 从文件读
#   echo '{"track":"drums"}' | ./mcp.sh call track.get -    # - = 从 stdin 读
#   ./mcp.sh call track.delete '{"track":"midi:…","confirm":true}' --envelope
#   ./mcp.sh upload /tmp/lead.wav                # → {"fileId": …}
#   ./mcp.sh download <downloadId> /tmp/drums.m4a
#
# 选项
#   --envelope    打印完整信封（ok / revision / warnings / error），而不是只打印 data
#   --compact     单行 JSON
#   --dry-run     等价于 arguments.dryRun = true（只校验，不落盘）
#
# 环境变量
#   ACAPELLA_MCP_URL     直接指定 http://127.0.0.1:<port>
#   ACAPELLA_MCP_TOKEN   覆盖 token（优先于文件）
#   ACAPELLA_AGENT_TOKEN 兼容旧名，同上
#
# 退出码
#   0 成功 · 1 工具返回 ok=false · 2 用法/参数错 · 3 连不上或没 token · 4 CONFLICT
#
set -uo pipefail

SELF="$(basename "$0")"
TIMEOUT="${ACAPELLA_MCP_TIMEOUT:-180}"
ENVELOPE=0
COMPACT=0
DRY_RUN=0

die() { echo "$SELF: $1" >&2; exit "${2:-3}"; }

# ---------------------------------------------------------------- 端点发现

# App 默认绑 47610，被占时顺延到 47620。客户端不该假设默认值 —— 设置页
# 显示的是实际端口，这里扫一遍是最省事又不猜的做法。
discover_base() {
  if [ -n "${ACAPELLA_MCP_URL:-}" ]; then
    printf '%s' "${ACAPELLA_MCP_URL%/}"
    return 0
  fi
  local port body
  for port in $(seq 47610 47620); do
    body="$(curl --noproxy '*' -s -m 1 "http://127.0.0.1:${port}/health" 2>/dev/null)"
    case "$body" in
      *'"listening"'*|*'"port"'*)
        printf 'http://127.0.0.1:%s' "$port"
        return 0
        ;;
    esac
  done
  return 1
}

ACTION="${1:-}"
[ $# -gt 0 ] && shift

# 看帮助不该要求 App 开着 —— 这是第一个会被新用户敲的命令。
case "$ACTION" in
  ""|-h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

BASE="$(discover_base)" || die "no Acapella MCP server on 127.0.0.1:47610–47620.
  → open Acapella, then Settings › AI Control, and turn the switch on."

# token 由 App 生成、由人复制。这里读的是**用户自己的副本**，不碰 App 容器：
# 容器路径随沙盒形态变化，翻它是错的（也是过去 CLI 反复踩的坑）。
TOKEN="${ACAPELLA_MCP_TOKEN:-${ACAPELLA_AGENT_TOKEN:-}}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.config/acapella/token" ]; then
  TOKEN="$(tr -d ' \t\r\n' < "$HOME/.config/acapella/token")"
fi
[ -n "$TOKEN" ] || die "no token.
  → copy it from Acapella › Settings › AI Control, then:
      mkdir -p ~/.config/acapella && pbpaste > ~/.config/acapella/token && chmod 600 ~/.config/acapella/token
    (or export ACAPELLA_MCP_TOKEN=…)"

post_mcp() {
  curl --noproxy '*' -s -m "$TIMEOUT" \
    -H 'Content-Type: application/json' \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer ${TOKEN}" \
    --data-binary "$1" \
    "${BASE}/mcp"
}

# 401/403 回的是裸信封（不是 JSON-RPC），这里把它翻译成一句人话。
guard_jsonrpc() {
  printf '%s' "$1" | jq -e 'has("jsonrpc")' >/dev/null 2>&1 && return 0
  local code
  code="$(printf '%s' "$1" | jq -r '.error.code // empty' 2>/dev/null)"
  case "$code" in
    UNAUTHORIZED|FORBIDDEN|"")
      die "POST /mcp rejected (${code:-empty response}).
  → token 不对或已失效：重新从 Acapella › Settings › AI Control 复制一遍。" 3
      ;;
    *)
      die "POST /mcp rejected: ${code}" 3
      ;;
  esac
}

# ---------------------------------------------------------------- 子命令

cmd_health() {
  local body
  body="$(curl --noproxy '*' -s -m 5 "${BASE}/health")" || die "GET /health failed at ${BASE}"
  printf '%s\n' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"
}

cmd_tools() {
  local raw
  raw="$(post_mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')" || die "POST /mcp failed"
  guard_jsonrpc "$raw"
  printf '%s' "$raw" | jq -e '.result.tools' >/dev/null 2>&1 || {
    printf '%s\n' "$raw" | jq . >&2 2>/dev/null || printf '%s\n' "$raw" >&2
    exit 3
  }
  if [ "$COMPACT" -eq 1 ]; then
    printf '%s' "$raw" | jq -c '.result.tools'
  else
    # 默认只给「名字 + 第一句描述 + 参数名」，够人看也够 AI 挑。
    printf '%s' "$raw" | jq -r '.result.tools[]
      | "\(.name)\t\(.description | split("\n")[0])\t\((.inputSchema.properties // {}) | keys_unsorted | join(", "))"'
  fi
}

# arguments 的来源：内联 JSON / @file / -
load_args() {
  local spec="$1"
  case "$spec" in
    ""|"{}") printf '{}' ;;
    @-|-)
      cat
      ;;
    @*)
      local path="${spec#@}"
      [ -f "$path" ] || die "arguments file not found: $path" 2
      cat "$path"
      ;;
    *)
      printf '%s' "$spec"
      ;;
  esac
}

cmd_call() {
  local tool="${1:-}"
  [ -n "$tool" ] || die "usage: $SELF call <tool> [JSON|@file|-]" 2
  shift || true

  # 剩下的非选项参数最多一个：arguments。
  local spec=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --envelope) ENVELOPE=1; shift ;;
      --compact) COMPACT=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -) spec="-"; shift ;;
      *) spec="$1"; shift ;;
    esac
  done

  local arguments
  if [ "$spec" = "-" ]; then
    arguments="$(cat)"
  else
    arguments="$(load_args "$spec")"
  fi

  # 校验是一段合法 JSON 对象：宁可在这里停下，也不要把坏参数发给服务端。
  printf '%s' "$arguments" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "arguments must be a JSON object, got: $arguments" 2
  if [ "$DRY_RUN" -eq 1 ]; then
    arguments="$(printf '%s' "$arguments" | jq -c '. + {dryRun: true}')"
  fi

  local payload response
  payload="$(jq -nc --arg name "$tool" --argjson args "$arguments" \
    '{jsonrpc:"2.0", id:1, method:"tools/call", params:{name:$name, arguments:$args}}')"
  response="$(post_mcp "$payload")" || die "POST /mcp failed"
  guard_jsonrpc "$response"

  # JSON-RPC 层错误（方法错、工具名不存在、参数结构不对）
  if printf '%s' "$response" | jq -e '.error' >/dev/null 2>&1; then
    printf '%s' "$response" | jq -r '"\(.error.code): \(.error.message)" + (if .error.data.hint then "\n  hint: \(.error.data.hint)" else "" end)' >&2
    exit 2
  fi

  local text is_error code
  is_error="$(printf '%s' "$response" | jq -r '.result.isError // false')"
  # 服务端把信封放在 structuredContent；缺了就从 text 里的 JSON 兜底解析。
  text="$(printf '%s' "$response" | jq -r '.result.structuredContent // (.result.content[0].text | fromjson?) // empty')"

  if [ "$ENVELOPE" -eq 1 ]; then
    if [ "$COMPACT" -eq 1 ]; then
      printf '%s\n' "$text" | jq -c .
    else
      printf '%s\n' "$text" | jq .
    fi
  else
    if [ "$COMPACT" -eq 1 ]; then
      printf '%s\n' "$text" | jq -c '.data // .'
    else
      printf '%s\n' "$text" | jq '.data // .'
    fi
    # warnings 只在没要信封时提示一句，免得被 data 盖掉。
    local warn
    warn="$(printf '%s\n' "$text" | jq -r '(.warnings // [])[]' 2>/dev/null)"
    [ -n "$warn" ] && printf '%s\n' "$warn" | sed 's/^/warning: /' >&2
  fi

  if [ "$is_error" = "true" ]; then
    code="$(printf '%s\n' "$text" | jq -r '.error.code // ""')"
    printf '%s\n' "$text" | jq -r '.error | "\(.code): \(.message)" + (if .hint then "\n  hint: \(.hint)" else "" end)' >&2
    case "$code" in
      CONFLICT) exit 4 ;;
      *) exit 1 ;;
    esac
  fi
  exit 0
}

cmd_upload() {
  local file="${1:-}"
  [ -n "$file" ] || die "usage: $SELF upload <file>" 2
  [ -f "$file" ] || die "no such file: $file" 2
  local name encoded body
  name="$(basename "$file")"
  # 文件名走 query（服务端会 percent-decode），body 是**裸字节**：不 base64、
  # 不 multipart，App 那边是边收边写盘的。
  encoded="$(printf '%s' "$name" | jq -sRr @uri)"
  body="$(curl --noproxy '*' -s -m "${ACAPELLA_MCP_UPLOAD_TIMEOUT:-300}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/octet-stream' \
    --data-binary "@${file}" \
    "${BASE}/upload?name=${encoded}")" || die "POST /upload failed"
  # 服务端回的是完整信封（ok / revision / data.fileId…），这里只摘 data。
  printf '%s\n' "$body" | jq -e '.data' >/dev/null 2>&1 \
    && printf '%s\n' "$body" | jq '.data' \
    || printf '%s\n' "$body" | jq .
}

cmd_download() {
  local id="${1:-}" out="${2:-}"
  [ -n "$id" ] || die "usage: $SELF download <downloadId> [outfile]" 2
  [ -n "$out" ] || out="./${id}"
  curl --noproxy '*' -s -f -m "${ACAPELLA_MCP_TIMEOUT:-180}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -o "$out" \
    "${BASE}/download/${id}" || die "GET /download/${id} failed (下载区只留 6 小时，过期要重新 export)" 3
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------- 分发

case "$ACTION" in
  health)   cmd_health ;;
  tools)    [ "${1:-}" = "--compact" ] && COMPACT=1; cmd_tools ;;
  call)     cmd_call "$@" ;;
  upload)   cmd_upload "$@" ;;
  download) cmd_download "$@" ;;
  *)
    die "unknown action: $ACTION (health / tools / call / upload / download / --help)" 2
    ;;
esac
