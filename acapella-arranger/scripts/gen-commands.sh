#!/usr/bin/env bash
#
# gen-commands.sh —— 重新生成 references/commands.md。
#
# 命令表是 CLI 自己吐出来的（`acapella docs`），不要手写：
# 命令一改，重跑本脚本，文档自动跟上。
#
# 用法
#   ./scripts/gen-commands.sh                 # 覆盖 ../references/commands.md
#   ./scripts/gen-commands.sh /tmp/out.md     # 写到别处
#   ACAPELLA_BIN=/path/to/acapella ./scripts/gen-commands.sh   # 开发时用本地构建
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HERE/../references/commands.md}"
BIN="${ACAPELLA_BIN:-acapella}"

if ! command -v "$BIN" >/dev/null 2>&1 && [ ! -x "$BIN" ]; then
  echo "gen-commands.sh: ${BIN} not found (set ACAPELLA_BIN=/path/to/acapella)" >&2
  exit 3
fi

mkdir -p "$(dirname "$DEST")"
DEST="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"
"$BIN" docs --out "$DEST"

# 命令数直接从生成的文档头部取（`共 N 条命令`），不要自己数表格行 —— 表格里还有选项表。
ROWS="$(grep -oE '共 [0-9]+ 条命令' "$DEST" | grep -oE '[0-9]+' || echo '?')"
echo "regenerated $DEST ($ROWS commands)"
