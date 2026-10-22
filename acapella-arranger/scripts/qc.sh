#!/usr/bin/env bash
#
# qc.sh —— 交付前的客观质检闸门。
#
# 为什么要包一层：`acapella qc mix` 返回 JSON，人要在几十行里找"过没过"；
# 脚本把阈值判断做掉，退出码就是结论 —— 0 合格、1 不合格。CI 或 AI 直接看码。
#
# 用法
#   ./qc.sh                     # 默认峰值上限 -0.3 dBFS，必须主唱有信号
#   ./qc.sh --max-peak -1.0     # 更严
#   ./qc.sh --json              # 只打印原始 JSON（转发给别的工具）
#   ./qc.sh --allow-no-lead     # 工程里没有主唱时放行（纯器乐）
#
# 退出码
#   0 通过 · 1 不合格 · 2 返回的 JSON 读不懂 · 3 acapella 调用失败
#
set -uo pipefail

MAX_PEAK="-0.3"
REQUIRE_LEAD=1
RAW_JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --max-peak) MAX_PEAK="${2:?--max-peak needs a number}"; shift 2 ;;
    --json) RAW_JSON=1; shift ;;
    --allow-no-lead) REQUIRE_LEAD=0; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "qc.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

if ! command -v acapella >/dev/null 2>&1; then
  echo "qc.sh: acapella is not on PATH (brew install govo/tap/acapella)" >&2
  exit 3
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "qc.sh: python3 is required" >&2
  exit 3
fi

OUT="$(acapella qc mix)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  echo "qc.sh: acapella qc mix failed (exit $STATUS)" >&2
  exit 3
fi

if [ "$RAW_JSON" -eq 1 ]; then
  printf '%s\n' "$OUT"
fi

printf '%s' "$OUT" | python3 -c '
import json, sys

data = json.load(sys.stdin)
max_peak = float(sys.argv[1])
require_lead = sys.argv[2] == "1"

peak = data.get("peakDbfs")
rms = data.get("rmsDbfs")
clipped = bool(data.get("clipped"))
clips = int(data.get("clipSampleCount") or 0)
duration = data.get("duration")
checks = data.get("checks") or {}
problems = data.get("problems") or []
tracks = data.get("tracks") or []

failures = list(problems)

# 服务端已经给出具体问题时，不要用同样的意思再报一遍。
# 本地检查只在两种情况下补充：① 服务端没给 problems（旧版本）；
# ② 用户把阈值调得比服务端更严（--max-peak -2.0）。
if not problems:
    if clipped or clips > 0:
        failures.append(f"{clips} clipped sample(s)")
    if peak is None:
        failures.append("no peakDbfs in the response")
    elif peak > max_peak:
        failures.append(f"peak {peak:.1f} dBFS > {max_peak:.1f} dBFS")
    if not checks.get("hasSignal", True):
        failures.append("the mix is silent")
    if checks.get("durationMatches") is False:
        failures.append("exported duration does not match the project")
    if require_lead and checks.get("leadHasSignal") is False:
        failures.append("the lead vocal has no signal (only backing was exported?)")
elif peak is not None and max_peak < -0.3 and peak > max_peak:
    failures.append(f"peak {peak:.1f} dBFS > your limit {max_peak:.1f} dBFS")

verdict = "PASS" if not failures else "FAIL"
# 先把缺值格式化掉：f-string 表达式里不能有反斜杠（Python < 3.12）。
peak_text = f"{peak}" if peak is not None else "?"
rms_text = f"{rms}" if rms is not None else "?"
duration_text = f"{duration}" if duration is not None else "?"
print(f"qc mix — {verdict}")
print(f"  peak      {peak_text} dBFS   limit {max_peak}")
print(f"  rms       {rms_text} dBFS")
print(f"  clipped   {clips} samples")
print(f"  duration  {duration_text} s")
if tracks:
    print("  tracks")
    for track in tracks:
        ok = "✓" if track.get("hasSignal") else "✗"
        source = track.get("source") or "?"
        name = track.get("name") or ""
        tp = track.get("peakDbfs")
        gain = track.get("gain")
        extra = f" · {name}" if name and name != source else ""
        print(f"    {ok} {source}{extra}   {tp} dBFS   gain {gain}")
if failures:
    print("  problems")
    for problem in failures:
        print(f"    - {problem}")

sys.exit(0 if not failures else 1)
' "$MAX_PEAK" "$REQUIRE_LEAD"
