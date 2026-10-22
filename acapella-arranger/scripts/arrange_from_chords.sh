#!/usr/bin/env bash
#
# arrange_from_chords.sh —— 给一份和弦进行，产出四条声部的 notes JSON。
#
# 这是「配方 2」的第 1 步：把 C Am F G 变成能直接喂给 `acapella notes replace` 的音符表。
# 乐理规则写在 references/music.md §4；本脚本是它的实现。
#
# 用法
#   ./arrange_from_chords.sh "C Am F G" --bars 8 --out ./parts
#   ./arrange_from_chords.sh "C Am F G Am F G C" --bars 16 --bpm 92 --melody "E4 G4 A4 G4"
#
# 参数
#   "和弦…"            空格分隔，支持 maj/min/7/maj7/m7/dim/aug/sus4/6/m6，N = 留白
#   --bars N           总小节数（默认 8）；和弦平均分配，每个至少 1 小节
#   --out DIR          JSON 写到哪里（默认 ./parts）
#   --bpm N            速度（默认 92），用来把拍换算成秒
#   --beats-per-bar N  拍号（默认 4）
#   --melody "E4 …"    主唱参照音，每个和弦一个；不给就用和弦根音高八度当参照
#   --print            只打印，不写文件
#
# 产出
#   bass.json arp.json pad.json high.json   [{start, duration, pitch, velocity}]
#   plan.json                              每条轨的建议音量/声像
#
set -uo pipefail

if [ $# -lt 1 ]; then
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

CHORDS="$1"; shift
BARS=8
OUT="./parts"
BPM=92
BPB=4
MELODY=""
PRINT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bars) BARS="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --bpm) BPM="${2:?}"; shift 2 ;;
    --beats-per-bar) BPB="${2:?}"; shift 2 ;;
    --melody) MELODY="${2:?}"; shift 2 ;;
    --print) PRINT=1; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "arrange_from_chords.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "arrange_from_chords.sh: python3 is required" >&2
  exit 3
fi

mkdir -p "$OUT"

python3 - "$CHORDS" "$BARS" "$OUT" "$BPM" "$BPB" "$MELODY" "$PRINT" <<'PY'
import json, os, sys

chords_text, bars_text, out_dir, bpm_text, bpb_text, melody_text, print_only = sys.argv[1:8]
bars = max(1, int(bars_text))
bpm = float(bpm_text)
bpb = max(1, int(bpb_text))
print_only = print_only == "1"
beat = 60.0 / bpm
bar_seconds = beat * bpb

# ---------- 和弦语法 ----------
QUALITIES = {
    "":      [0, 4, 7],
    "maj":   [0, 4, 7],
    "min":   [0, 3, 7],
    "m":     [0, 3, 7],
    "7":     [0, 4, 7, 10],
    "maj7":  [0, 4, 7, 11],
    "M7":    [0, 4, 7, 11],
    "m7":    [0, 3, 7, 10],
    "min7":  [0, 3, 7, 10],
    "dim":   [0, 3, 6],
    "aug":   [0, 4, 8],
    "sus4":  [0, 5, 7],
    "6":     [0, 4, 7, 9],
    "m6":    [0, 3, 7, 9],
}
LETTER = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

def parse_pitch(text):
    s = text.strip()
    name = s[0].upper()
    if name not in LETTER:
        raise SystemExit(f"bad note name: {text}")
    rest = s[1:]
    semis = LETTER[name]
    while rest and rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    octave = int(rest) if rest else 4
    return semis + (octave + 1) * 12

def parse_chord(text):
    if text.upper() == "N":
        return None
    root_name = text[0].upper()
    if root_name not in LETTER:
        raise SystemExit(f"bad chord: {text}")
    rest = text[1:]
    root = LETTER[root_name]
    while rest and rest[0] in "#b":
        root += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    quality = rest
    if quality not in QUALITIES:
        raise SystemExit(f"unknown chord quality `{quality}` in {text} (see music.md §3)")
    return root % 12, QUALITIES[quality]

CHORD_LIST = [parse_chord(token) for token in chords_text.split()]
if not CHORD_LIST:
    raise SystemExit("no chords given")

melody_notes = [parse_pitch(t) for t in melody_text.split()] if melody_text.strip() else []
if melody_notes and len(melody_notes) != len(CHORD_LIST):
    raise SystemExit(f"--melody has {len(melody_notes)} notes but there are {len(CHORD_LIST)} chords")

# 每个和弦占多少小节（至少 1）
span = max(1, bars // len(CHORD_LIST))

def chord_tones(chord, floor=0):
    if chord is None:
        return []
    pc, intervals = chord
    # MIDI 48 = C3：floor//12 是"这个音所在的八度"，再加音级。
    base = 12 * (floor // 12) + pc
    while base < floor:
        base += 12
    return [base + i for i in intervals]

def nearest_in_range(tones, low, high, prefer=None):
    """在 [low, high] 里取最接近 prefer 的和弦内音；没有就升/降八度再找。"""
    candidates = [t for t in tones if low <= t <= high]
    if not candidates:
        for shift in (12, -12, 24, -24):
            candidates = [t + shift for t in tones if low <= t + shift <= high]
            if candidates:
                break
    if not candidates:
        return (prefer if prefer is not None else low)
    if prefer is None:
        return min(candidates)
    return min(candidates, key=lambda t: (abs(t - prefer), t))

bass_notes, arp_notes, pad_notes, high_notes = [], [], [], []

for index, chord in enumerate(CHORD_LIST):
    start_bar = index * span
    start = start_bar * bar_seconds
    length = span * bar_seconds
    if chord is None:
        continue

    pc, intervals = chord
    tones_low = chord_tones(chord, floor=33)

    # 1) 贝斯：根音降到 33..55，每两拍一个（half）
    bass_root = tones_low[0]
    while bass_root > 55:
        bass_root -= 12
    step = 2 * beat if bpb >= 4 else beat
    t = start
    while t < start + length - 1e-6:
        bass_notes.append({
            "start": round(t, 3),
            "duration": round(min(step, start + length - t), 3),
            "pitch": bass_root,
            "velocity": 0.85,
        })
        t += step

    # 2) 琶音：每拍一个，1-3-5 循环，落进 38..88
    arp_tones = chord_tones(chord, floor=48)
    arp_tones = [t_ for t_ in arp_tones if 38 <= t_ <= 88] or chord_tones(chord, floor=60)
    t = start
    step_index = 0
    while t < start + length - 1e-6:
        pitch = arp_tones[step_index % len(arp_tones)]
        if step_index % (len(arp_tones) * 2) >= len(arp_tones):
            pitch += 12  # 第二遍升八度，避免机械重复
        arp_notes.append({
            "start": round(t, 3),
            "duration": round(min(beat, start + length - t), 3),
            "pitch": min(max(pitch, 38), 88),
            "velocity": 0.7,
        })
        step_index += 1
        t += beat

    # 3) 长音垫：主唱上方 3–8 度内的和弦内音
    #    没有给 --melody 时，把和弦根音的中音区（C4 附近）当主唱参照，
    #    别用高八度 —— 那会把垫音推到 C6，听起来像哨音。
    melody = melody_notes[index] if melody_notes else pc + 60
    pad_pitch = nearest_in_range(chord_tones(chord, floor=max(40, melody - 12)),
                                 melody + 3, melody + 8, prefer=melody + 4)
    pad_notes.append({
        "start": round(start, 3),
        "duration": round(length, 3),
        "pitch": pad_pitch,
        "velocity": 0.6,
    })

    # 4) 高音和声：主唱上方 5–12 度，优先五度
    high_pitch = nearest_in_range(chord_tones(chord, floor=max(40, melody - 12)),
                                  melody + 5, melody + 12, prefer=melody + 7)
    high_notes.append({
        "start": round(start, 3),
        "duration": round(length, 3),
        "pitch": high_pitch,
        "velocity": 0.6,
    })

# ---------- 平行五八度检查（只报，不改） ----------
warnings = []
for i in range(1, min(len(pad_notes), len(high_notes))):
    lower_delta = pad_notes[i]["pitch"] - pad_notes[i - 1]["pitch"]
    upper_delta = high_notes[i]["pitch"] - high_notes[i - 1]["pitch"]
    interval_before = high_notes[i - 1]["pitch"] - pad_notes[i - 1]["pitch"]
    interval_after = high_notes[i]["pitch"] - pad_notes[i]["pitch"]
    same_direction = lower_delta * upper_delta > 0
    parallel = interval_before % 12 == interval_after % 12 and interval_after % 12 in (0, 7)
    if same_direction and parallel:
        warnings.append(
            f"bar {i * span + 1}: pad/high move in parallel "
            f"{'fifths' if interval_after % 12 == 7 else 'octaves'} — see music.md §4"
        )

parts = {
    "bass": (bass_notes,  {"volume": 0.85, "pan": 0}),
    "arp":  (arp_notes,   {"volume": 0.6,  "pan": -0.15}),
    "pad":  (pad_notes,   {"volume": 0.5,  "pan": 0.25}),
    "high": (high_notes,  {"volume": 0.45, "pan": 0.3}),
}

plan = {
    "bpm": bpm,
    "beatsPerBar": bpb,
    "bars": bars,
    "chords": chords_text.split(),
    "tracks": {name: {"notes": len(data), **mix} for name, (data, mix) in parts.items()},
    "warnings": warnings,
}

if print_only:
    for name, (data, mix) in parts.items():
        print(f"--- {name}.json  ({len(data)} notes, volume {mix['volume']}, pan {mix['pan']})")
else:
    for name, (data, _mix) in parts.items():
        path = os.path.join(out_dir, f"{name}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print(f"wrote {path}  ({len(data)} notes)")
    plan_path = os.path.join(out_dir, "plan.json")
    with open(plan_path, "w", encoding="utf-8") as fh:
        json.dump(plan, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"wrote {plan_path}")

for warning in warnings:
    print(f"warning: {warning}", file=sys.stderr)

if warnings:
    sys.exit(0)

print()
if print_only:
    print("(--print: nothing was written; drop --print to emit the four JSON files)")
else:
    print("next  (把 @track:\"bass\" 换成你工程里真实的轨名；轨名要先 track list 确认唯一):")
    for name, (_data, _mix) in parts.items():
        print(f'  acapella notes replace --track @track:"{name}" --notes {out_dir}/{name}.json')
    print("  # 四条都写完，再逐条 track render（串行）")
PY

exit $?
