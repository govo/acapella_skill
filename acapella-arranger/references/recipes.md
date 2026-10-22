# 六个完整配方

每个配方都是**可复制的命令序列**。`<…>` 是占位符，`midi:…` 要换成 `track list` 里的真实 token。

---

## 配方 1：从零建一个空工程，加两条人声轨

```bash
acapella doctor
acapella project create "练习 - 晴天" --bpm 92 --beats-per-bar 4 --bars 64
```

预期：`data` 就是完整快照，`project.isBlank = true`，`tracks` 只有一条默认人声轨（或空）。
`revision` 从 0 变 1。

```bash
acapella track add "主唱" --kind vocal
acapella track add "和声" --kind vocal
acapella track list
```

预期：两条 `kind = "stem"`、`role = "leadVocal"`、`hasAudio = false`（还没录音，正常）。

**坑**：空工程里 `--kind midi` 也能加，但空工程没有节拍网格 → 写音符前先
`beat set --bpm 92`。分轨工程（`isBlank = false`）里 `track add --kind vocal` 会
`UNSUPPORTED`，只能加 MIDI 轨。

---

## 配方 2：给已有工程配四声部（和弦 → 音符 → 渲染）

```bash
acapella state | jq '{project: .project.name, bpm: .beat.bpm, grid: (.beat.isFallback|not)}'
```

`grid = false` 就先 `acapella beat set --bpm 92`（或用 `beat analyze --wait`）。

```bash
# 1. 生成 4 条声部的音符（每小节一个和弦）
scripts/arrange_from_chords.sh "C Am F G" --bars 8 --out ./parts

# 2. 建 4 条 MIDI 轨
acapella track add "Bass"  --kind midi
acapella track add "Arp"   --kind midi
acapella track add "Pad"   --kind midi
acapella track add "High"  --kind midi

# 3. 写音符（一次写完整段，别一个音一条命令）
acapella notes replace --track @track:"Bass" --notes @parts/bass.json
acapella notes replace --track @track:"Arp"  --notes @parts/arp.json
acapella notes replace --track @track:"Pad"  --notes @parts/pad.json
acapella notes replace --track @track:"High" --notes @parts/high.json

# 4. 四条都写完后，一次渲染（串行，别并发）
acapella track render --track @track:"Bass"
acapella track render --track @track:"Arp"
acapella track render --track @track:"Pad"
acapella track render --track @track:"High"

# 5. 按 music.md 的起点混音
acapella track mix --track @track:"Bass" --volume 0.85
acapella track mix --track @track:"Arp"  --volume 0.6 --pan L15
acapella track mix --track @track:"Pad"  --volume 0.5 --pan R25
acapella track mix --track @track:"High" --volume 0.45 --pan R30
```

预期：每条 `notes replace` 返回 `noteCount`；`track render` 后该轨 `hasAudio = true`。

**坑**：
- `@track:"Bass"` 是**名字寻址**，重名会 `BAD_REQUEST` —— 先用 `track list` 确认唯一。
- `render` 是重活，一条一条来；四条并发会把 App 的渲染队列堵住。
- 写错音符不要删轨重建：`notes patch --transpose -2` 更快。

---

## 配方 3：设一个副歌循环来练

```bash
acapella section list
```

有段落就直接用它的时间：

```bash
acapella loop set 17:1 25:1        # 第 17 小节到第 25 小节（不含 25）
acapella loop enable
acapella transport seek 17:1
acapella transport play
```

没有段落（`sections` 为空）就自己算：副歌通常在第 2 段，`16–24` 小节。

**坑**：
- `loop set` 的第二个参数是**结束点**，区间是半开的 `[a, b)`。
- 长度 < 1 秒会被拒（`PRECONDITION_FAILED`）。
- `loop enable` 之前必须 `loop.a/b` 都非空，否则 `PRECONDITION_FAILED`。
- 练习结束 `loop clear`，否则下次播放会跳回 A 点。

---

## 配方 4：修一条"听不见"的轨

诊断顺序（不要跳）：

```bash
acapella state | jq '.tracks[] | select(.token=="midi:…")'
```

| 看到 | 原因 | 修法 |
| --- | --- | --- |
| `hasAudio = false`, `noteCount > 0` | 写了音符没渲染 | `track render --track midi:…` |
| `noteCount = 0` | 没写音符 | `notes replace …` |
| `isMuted = true` | 被静音 | `track mix --track … --mute off` |
| `volume = 0` | 音量为 0 | `track mix --track … --volume 0.8` |
| 其他轨 `isSoloed = true` | 有轨在独奏 | 逐条 `--solo off` |
| 都正常 | 可能被折叠/超出工程长度 | `track fold --track … --fold off`，看音符是否在 0…duration 内 |

`notes get --track midi:… --limit 5` 可以确认音符真在里面以及起始时间。

---

## 配方 5：交付一版混音（带质检）

```bash
acapella qc mix            # 先质检，不合格别导出
acapella export mix        # 返回绝对路径
scripts/qc.sh              # 封装版：阈值不过退出非 0
```

`qc mix` 返回的关键字段：

```jsonc
{
  "ok": true,
  "duration": 214.6,
  "peakDbfs": -1.2,
  "rmsDbfs": -16.8,
  "clipped": false,
  "clipSampleCount": 0,
  "silentSpans": [],
  "tracks": [ { "source": "vocals", "name": "人声", "peakDbfs": -1.5, "hasSignal": true, "gain": 1 } ],
  "checks": { "noClipping": true, "peakHeadroom": true, "hasSignal": true,
              "durationMatches": true, "leadHasSignal": true },
  "problems": []
}
```

判定：`clipped = false`、`peakDbfs <= -0.3`、`checks.leadHasSignal = true`、`problems` 为空。

**坑**：
- 导出会**临时渲染一遍**，比 `qc mix` 慢；先 QC 再导出能省一次。
- MIDI 轨不参与导出，必须先 `track render`（`hasAudio = true` 才有声音）。
- 文件落在 App 容器 `Application Support/AgentControl/Exports/`，把返回的绝对路径给用户；
  **不要**用 `cp` 去猜位置。

---

## 配方 6：排查"成片只有伴奏，没有人声"

这是最典型的一次事故。按顺序查：

```bash
acapella state | jq '{solo: [.tracks[] | select(.isSoloed) | .token],
                      muted: [.tracks[] | select(.isMuted) | .token],
                      noAudio: [.tracks[] | select(.hasAudio == false) | .token],
                      lead: [.tracks[] | select(.role=="leadVocal") | {token, volume, pan}]}'
```

1. `solo` 非空 → 有轨在独奏，其他全被压掉：逐条 `--solo off`。
2. `muted` 含主唱 → `--mute off`。
3. `noAudio` 含主唱的 MIDI 轨 → `track render`。
4. 主唱 `volume = 0` → `--volume 1`。
5. 都正常但仍听不到 → `notes get` 看音符时间是否落在 `0…project.duration` 之外。

导出前永远先看这一条：**导出只乘轨道音量，不乘独奏/静音**（历史事故：某次导出把伴奏乘 0，
成片只剩录音）。所以"导出听起来不对"和"播放听起来不对"可能不是同一个原因 —— 以 `qc mix` 的
`tracks[].hasSignal` 与 `checks.leadHasSignal` 为准。
