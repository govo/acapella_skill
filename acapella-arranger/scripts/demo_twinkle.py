#!/usr/bin/env python3
"""
demo_twinkle.py —— 用《小星星》从头建一首有风格的小样（端到端演示）。

它演示的是「AI 通过 MCP 做音乐」的最小完整闭环：
    建空工程 → 加 4 条 MIDI 轨 → 写音符 → 调混音 → 渲染 → 导出 → 客观质检

为什么用脚本而不是让 AI 逐条调用工具：编曲最怕"算错一个 beat"。这里所有时间
都由 BPM 推出来（量化到 beat 网格），音符表一次写整轨，AI 只负责决定"和声走几度、
低音怎么走"，算术交给代码 —— 这正是 SKILL 里"不要让模型做十六分音符算术"的意思。

用法
    ./demo_twinkle.py                          # 轻快流行，100 BPM
    ./demo_twinkle.py --style ballad --name "小星星·抒情"
    ./demo_twinkle.py --plan                   # 只看编排统计，不连 App
    ./demo_twinkle.py --bpm 112 --keep-json    # 保留生成的音符 JSON
    ./demo_twinkle.py --url http://127.0.0.1:47612   # 端口顺延过时手动指定

token：ACAPELLA_MCP_TOKEN，或 ~/.config/acapella/token（从 App 设置页复制）。

退出码
    0 成功 · 1 编曲/参数问题 · 3 连不上 App · 4 某一步被服务端拒绝
"""

import argparse
import json
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.request

# ---------------------------------------------------------------- 音高工具

# C 大调音阶（C4=60 起，两个八度），用来算"级数上的三度"而不是固定 +3/+4 半音。
SCALE = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84]

# 每小节一个和弦：C C F C | G C G C | C C F C
CHORDS = ["C", "C", "F", "C", "G", "C", "G", "C", "C", "C", "F", "C"]

# 和弦 → (低音根音, 低音五度, 琶音三音)
CHORD_TONES = {
    "C": (48, 55, (60, 64, 67)),
    "F": (41, 48, (65, 69, 72)),
    "G": (43, 50, (67, 71, 74)),
}


def third_below(pitch):
    """调内三度下行；不在音阶里就退回 -3 半音（黑键也能得到合理的和声）。"""
    if pitch in SCALE:
        index = SCALE.index(pitch)
        if index >= 2:
            return SCALE[index - 2]
    return pitch - 3


# ---------------------------------------------------------------- 旋律

# 《小星星》12 小节，每项 (起始拍, 时值拍, MIDI)。拍从 0 起，全曲 4/4。
MELODY = [
    # 第一句
    (0, 1, 60), (1, 1, 60), (2, 1, 67), (3, 1, 67),
    (4, 1, 69), (5, 1, 69), (6, 2, 67),
    (8, 1, 65), (9, 1, 65), (10, 1, 64), (11, 1, 64),
    (12, 1, 62), (13, 1, 62), (14, 2, 60),
    # 第二句
    (16, 1, 67), (17, 1, 67), (18, 1, 65), (19, 1, 65),
    (20, 1, 64), (21, 1, 64), (22, 2, 62),
    (24, 1, 67), (25, 1, 67), (26, 1, 65), (27, 1, 65),
    (28, 1, 64), (29, 1, 64), (30, 2, 62),
    # 再现 + 收尾
    (32, 1, 60), (33, 1, 60), (34, 1, 67), (35, 1, 67),
    (36, 1, 69), (37, 1, 69), (38, 2, 67),
    (40, 1, 65), (41, 1, 65), (42, 1, 64), (43, 1, 64),
    (44, 1, 62), (45, 1, 62), (46, 4, 60),
]

BARS = 12

# 风格只影响"伴奏怎么写"，旋律永远是同一段 —— 这样才能对比出风格差异。
STYLES = {
    "pop": {
        "label": "轻快流行",
        "bpm": 100,
        "harmony": True,
        "arp": True,
        "bass": "root-fifth",     # 每小节：根音两拍 + 五度两拍
        "velocities": (0.85, 0.50, 0.80, 0.45),
    },
    "ballad": {
        "label": "抒情",
        "bpm": 72,
        "harmony": True,
        "arp": False,             # 换成铺底长音
        "bass": "root-whole",     # 每小节一个全音符
        "velocities": (0.80, 0.45, 0.70, 0.40),
    },
    "folk": {
        "label": "民谣",
        "bpm": 120,
        "harmony": False,
        "arp": True,
        "bass": "root-fifth",
        "velocities": (0.82, 0.0, 0.75, 0.55),
    },
}


def to_seconds(beat, bpm):
    return round(beat * 60.0 / bpm, 3)


def pan_text(value):
    """声像用服务端接受的记法（L18 / R22 / 0），不要喂 "+0.00" 这种带正号的数字。"""
    if abs(value) < 0.01:
        return "0"
    return "%s%.0f" % ("L" if value < 0 else "R", abs(value) * 100)


def make_part(style, bpm):
    """返回 [(轨名, 音符列表, 音量, 声像)]，音符已换算成秒。"""
    spec = STYLES[style]
    lead_v, harm_v, bass_v, arp_v = spec["velocities"]
    beat = 60.0 / bpm

    lead = [
        {"start": to_seconds(b, bpm), "duration": to_seconds(d, bpm),
         "pitch": p, "velocity": lead_v}
        for b, d, p in MELODY
    ]

    harmony = []
    if spec["harmony"]:
        for b, d, p in MELODY:
            harmony.append({
                "start": to_seconds(b, bpm),
                "duration": to_seconds(max(d - 0.1, 0.4), bpm),
                "pitch": third_below(p),
                "velocity": harm_v,
            })

    bass = []
    for bar, chord in enumerate(CHORDS):
        root, fifth, _ = CHORD_TONES[chord]
        start_beat = bar * 4
        last_bar = bar == len(CHORDS) - 1
        if spec["bass"] == "root-whole" or last_bar:
            bass.append({"start": to_seconds(start_beat, bpm), "duration": to_seconds(4, bpm),
                         "pitch": root, "velocity": bass_v})
        else:
            bass.append({"start": to_seconds(start_beat, bpm), "duration": to_seconds(2, bpm),
                         "pitch": root, "velocity": bass_v})
            bass.append({"start": to_seconds(start_beat + 2, bpm), "duration": to_seconds(2, bpm),
                         "pitch": fifth, "velocity": bass_v})

    arp = []
    for bar, chord in enumerate(CHORDS):
        root, _, tones = CHORD_TONES[chord]
        base = bar * 4
        if spec["arp"]:
            # 八分音符分解和弦：根 三 五 高八度 五 三 根 三
            pattern = [tones[0], tones[1], tones[2], tones[0] + 12,
                       tones[2], tones[1], tones[0], tones[1]]
            for i, pitch in enumerate(pattern):
                arp.append({
                    "start": to_seconds(base + i * 0.5, bpm),
                    "duration": to_seconds(0.45, bpm),
                    "pitch": pitch,
                    "velocity": arp_v,
                })
        else:
            arp.append({
                "start": to_seconds(base, bpm),
                "duration": to_seconds(4, bpm),
                "pitch": tones[0] - 12 if tones[0] >= 60 else tones[0],
                "velocity": arp_v,
            })

    # 电平按"四条轨加起来仍留余量"定：单轨峰值都低于 -3 dBFS，混出来才不会顶到 0。
    # 首版用 0.85/0.62/0.80/0.50 时混音峰值到了 -0.1 dBFS，质检判「没有余量」——
    # 这不是 bug，是配平没做够。
    tracks = [
        ("Lead 小星星", lead, 0.75, 0.0),
        ("Harmony 三度", harmony, 0.52, -0.18),
        ("Bass 低音", bass, 0.68, 0.0),
        ("Arp 琶音", arp, 0.42, 0.22),
    ]
    return [t for t in tracks if t[1]]


# ---------------------------------------------------------------- MCP 客户端

TOKEN_FILE = os.path.expanduser("~/.config/acapella/token")


class MCPError(Exception):
    """带退出码的错误：3 = 连不上，4 = 服务端拒绝。"""

    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


def read_token():
    for key in ("ACAPELLA_MCP_TOKEN", "ACAPELLA_AGENT_TOKEN"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, encoding="utf-8") as handle:
            return handle.read().strip()
    raise MCPError(
        "缺少 token：从 Acapella › 设置 › AI 控制 复制，然后\n"
        "  mkdir -p ~/.config/acapella && pbpaste > ~/.config/acapella/token && chmod 600 该文件\n"
        "（或 export ACAPELLA_MCP_TOKEN=…）", 3)


class MCPClient:
    """只做三件事：发现端口、发 tools/call、把信封拆成 data。"""

    def __init__(self, base=None, timeout=180):
        self.token = read_token()
        self.timeout = timeout
        self.base = (base or self._discover()).rstrip("/")

    # App 默认 47610，被占时顺延到 47620 —— 扫一段比猜默认值可靠。
    def _discover(self):
        for port in range(47610, 47621):
            url = "http://127.0.0.1:%d" % port
            try:
                with urllib.request.urlopen(url + "/health", timeout=1) as response:
                    if b"listening" in response.read():
                        return url
            except (urllib.error.URLError, OSError):
                continue
        raise MCPError(
            "127.0.0.1:47610–47620 上没有 Acapella 的 MCP 服务：\n"
            "  → 打开 App，设置 › AI 控制，把开关打开", 3)

    def _post(self, payload):
        request = urllib.request.Request(
            self.base + "/mcp",
            data=json.dumps(payload).encode(),
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
                "Authorization": "Bearer " + self.token,
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            if error.code in (401, 403):
                raise MCPError("token 被拒（HTTP %d）：重新从设置页复制一遍" % error.code, 3)
            raise MCPError("POST /mcp → HTTP %d: %s" % (error.code, body[:300]), 3)
        except (urllib.error.URLError, OSError) as error:
            raise MCPError("连不上 %s：%s" % (self.base, error), 3)

    def health(self):
        with urllib.request.urlopen(self.base + "/health", timeout=5) as response:
            return json.loads(response.read())

    def call(self, tool, **arguments):
        response = self._post({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": tool, "arguments": arguments},
        })
        if "error" in response:
            error = response["error"]
            hint = (error.get("data") or {}).get("hint")
            raise MCPError("%s 失败：%s%s" % (
                tool, error.get("message"), "\n  hint: " + hint if hint else ""), 4)
        result = response.get("result") or {}
        envelope = result.get("structuredContent")
        if envelope is None:
            text = (result.get("content") or [{}])[0].get("text") or "{}"
            envelope = json.loads(text)
        if not envelope.get("ok", False):
            error = envelope.get("error") or {}
            hint = error.get("hint")
            raise MCPError("%s 被拒绝：%s · %s%s" % (
                tool, error.get("code"), error.get("message"),
                "\n  hint: " + hint if hint else ""), 4)
        for warning in envelope.get("warnings") or []:
            print("  ! %s: %s" % (tool, warning), file=sys.stderr)
        return envelope.get("data") or {}


# ---------------------------------------------------------------- 主流程

def main():
    parser = argparse.ArgumentParser(description="用小星星旋律生成一首有风格的小样")
    parser.add_argument("--name", default=None, help="工程名（默认按风格生成）")
    parser.add_argument("--style", default="pop", choices=sorted(STYLES), help="风格")
    parser.add_argument("--bpm", type=float, default=None, help="覆盖风格的默认 BPM")
    parser.add_argument("--url", default=None, help="MCP 端点（默认自动扫 47610–47620）")
    parser.add_argument("--plan", action="store_true", help="只打印编排统计，不发请求")
    parser.add_argument("--keep-json", action="store_true", help="保留音符 JSON")
    parser.add_argument("--no-export", action="store_true", help="不导出、不质检（只建工程）")
    args = parser.parse_args()

    spec = STYLES[args.style]
    bpm = args.bpm or spec["bpm"]
    name = args.name or ("小星星 · %s" % spec["label"])
    parts = make_part(args.style, bpm)

    print("小星星 · %s / %.0f BPM / %d 小节" % (spec["label"], bpm, BARS))
    for track_name, notes, volume, pan in parts:
        lowest = min(n["pitch"] for n in notes)
        highest = max(n["pitch"] for n in notes)
        print("  %-12s %3d 个音符  音域 %d…%d  音量 %.2f  声像 %+.2f"
              % (track_name, len(notes), lowest, highest, volume, pan))

    if args.plan:
        return 0

    client = MCPClient(args.url)

    # 0. 先确认 App 在监听：连不上时后面每一步都会以 exit 3 失败，先说清楚。
    client.call("ping")

    # 1. 建空工程（会自动打开，返回完整快照）
    state = client.call(
        "project.create",
        name=name,
        bpm=round(bpm),
        beatsPerBar=4,
        bars=BARS + 2,                    # 留两小节尾音
    )
    project = state.get("project", {})
    print("\n[1/7] 工程已建：%s (%s)" % (project.get("name", name), project.get("id", "?")))

    tempdir = tempfile.mkdtemp(prefix="twinkle-")
    created = []
    try:
        # 2. 加轨（--kind midi：空 MIDI 轨，空工程与导入工程都支持）
        for track_name, _, _, _ in parts:
            result = client.call("track.add", name=track_name, kind="midi")
            created.append(result["track"]["token"])
        print("[2/7] 已加 %d 条 MIDI 轨：%s" % (len(created), ", ".join(created)))

        # 3. 写音符（整轨替换，服务端会自动重渲染一次）
        for (track_name, notes, _, _), token in zip(parts, created):
            path = os.path.join(tempdir, token.replace(":", "_") + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(notes, handle)
            # 音符作为 JSON 数组直接进 arguments（MCP 没有 @file 这回事）
            result = client.call("notes.replace", track=token, notes=notes)
            printed = result.get("track", {}).get("noteCount", len(notes))
            print("[3/7] %-12s 写入 %s 个音符" % (track_name, printed))

        # 4. 混音（音量/声像；solo 一律不碰 —— 它会让别的轨在导出里静音）
        for (track_name, _, volume, pan), token in zip(parts, created):
            client.call("track.mix", track=token,
                        volume="%.2f" % volume, pan=pan_text(pan))
        print("[4/7] 混音完成")

        # 5. 渲染：MIDI 轨要先落成音频才能进导出（导出源读的是渲染 WAV）
        for (track_name, _, _, _), token in zip(parts, created):
            result = client.call("track.render", track=token)
            if not result.get("rendered"):
                print("  ! %s 渲染失败，导出会缺这条轨" % track_name, file=sys.stderr)
            else:
                print("[5/7] %-12s 已渲染" % track_name)

        if args.no_export:
            print("\n工程已保存。用 `project.list` 找到它，或在 App 里打开试听。")
            return 0

        # 6. 导出混音（文件落在 App 容器的 Exports/ 下，返回值带绝对路径）
        exported = client.call("export.mix")
        files = exported.get("files", [])
        print("[6/7] 导出：%s" % (files[0] if files else "(没有文件)"))

        # 7. 客观质检 —— AI 不会听，这是唯一能判断"有没有声音/有没有削波"的手段
        report = client.call("qc.mix")
        print("[7/7] 质检：%s" % json.dumps(report, ensure_ascii=False))
    finally:
        if args.keep_json:
            print("\n音符 JSON 保留在：%s" % tempdir)
        else:
            shutil.rmtree(tempdir, ignore_errors=True)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MCPError as error:
        print("demo_twinkle: %s" % error, file=sys.stderr)
        sys.exit(error.code)
    except KeyboardInterrupt:
        sys.exit(130)
