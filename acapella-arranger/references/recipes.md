# 十个完整配方

每个配方都是**可复制的调用序列**。`<…>` 是占位符，`midi:…` 要换成 `track.list` 里的真实 token。

两种写法等价，任选一种：

```jsonc
tools/call name=track.mix  { "track": "drums", "volume": "-3dB" }     // 原生 MCP 工具
scripts/mcp.sh call track.mix '{"track":"drums","volume":"-3dB"}'     // 只有 shell 时
```

---

## 配方 1：从零建一个空工程，加两条人声轨

```bash
scripts/mcp.sh health
scripts/mcp.sh call project.create '{"name":"练习 - 晴天","bpm":92,"beatsPerBar":4,"bars":64}'
```

预期：返回就是完整快照，`project.isBlank = true`，`tracks` 只有一条默认人声轨（或空）。
`revision` 从 0 变 1。

```bash
scripts/mcp.sh call track.add '{"name":"主唱","kind":"recording"}'
scripts/mcp.sh call track.add '{"name":"和声","kind":"recording"}'
scripts/mcp.sh call track.list
```

预期：两条 `kind = "midi"`、`role = "recording"`、`isRecordingTrack = true`、
`hasAudio = false`（还没录音，正常）。它们是**录音轨**：麦克风图标，`take.import` / 录音的落点。

想写音符就建另一种：`track.add {"name":"Bass","kind":"midi"}` → `role = "midi"`（键盘图标）。

**坑**：两种轨都只能在空工程里加。分轨工程（`isBlank = false`）里 `kind: "recording"`
会报 `PRECONDITION_FAILED`（分轨工程只有分轨 + 由分轨派生的轨），`kind: "midi"` 仍可用。
`kind: "vocal"` 是 `recording` 的旧别名，别在新方案里用。

---

## 配方 2：给已有工程配四声部（和弦 → 音符 → 渲染）

```bash
scripts/mcp.sh call state | jq '{project: .project.name, bpm: .beat.bpm, grid: (.beat.isFallback|not)}'
```

`grid = false` 就先 `beat.set {"bpm":92}`（或 `beat.analyze` + `job.get` 轮询）。

```bash
# 1. 生成 4 条声部的音符（每小节一个和弦）
scripts/arrange_from_chords.sh "C Am F G" --bars 8 --out ./parts

# 2. 建 4 条 MIDI 轨
for n in Bass Arp Pad High; do
  scripts/mcp.sh call track.add "{\"name\":\"$n\",\"kind\":\"midi\"}" >/dev/null
done

# 3. 写音符（一次写完整段，别一个音一条调用）
scripts/mcp.sh call notes.replace "$(jq -cn --arg t '@track:"Bass"' --slurpfile n ./parts/bass.json '{track:$t, notes:$n[0]}')"
scripts/mcp.sh call notes.replace "$(jq -cn --arg t '@track:"Arp"'  --slurpfile n ./parts/arp.json  '{track:$t, notes:$n[0]}')"
scripts/mcp.sh call notes.replace "$(jq -cn --arg t '@track:"Pad"'  --slurpfile n ./parts/pad.json  '{track:$t, notes:$n[0]}')"
scripts/mcp.sh call notes.replace "$(jq -cn --arg t '@track:"High"' --slurpfile n ./parts/high.json '{track:$t, notes:$n[0]}')"

# 4. 四条都写完后，一次渲染（串行，别并发）
for n in Bass Arp Pad High; do
  scripts/mcp.sh call track.render "{\"track\":\"@track:\\\"$n\\\"\"}" >/dev/null
done

# 5. 按 music.md 的起点混音
scripts/mcp.sh call track.mix '{"track":"@track:\"Bass\"","volume":"0.85"}'
scripts/mcp.sh call track.mix '{"track":"@track:\"Arp\"","volume":"0.6","pan":"L15"}'
scripts/mcp.sh call track.mix '{"track":"@track:\"Pad\"","volume":"0.5","pan":"R25"}'
scripts/mcp.sh call track.mix '{"track":"@track:\"High\"","volume":"0.45","pan":"R30"}'
```

预期：每条 `notes.replace` 返回 `noteCount`；`track.render` 后该轨 `hasAudio = true`。

**坑**：
- `@track:"Bass"` 是**名字寻址**，重名会 `BAD_REQUEST` —— 先用 `track.list` 确认唯一。
- `render` 是重活，一条一条来；四条并发会把 App 的渲染队列堵住。
- 写错音符不要删轨重建：`notes.patch {"transpose": -2}` 更快。
- 音符是**内联 JSON 数组**，不是文件路径。文件在客户端读好再塞进 `notes`（上面用 `jq --slurpfile` 拼）。

---

## 配方 3：设一个副歌循环来练

```bash
scripts/mcp.sh call section.list
```

有段落就直接用它的时间：

```bash
scripts/mcp.sh call loop.set '{"a":"17:1","b":"25:1"}'   # 第 17 小节到第 25 小节（不含 25）
scripts/mcp.sh call loop.enable
scripts/mcp.sh call transport.seek '{"to":"17:1"}'
scripts/mcp.sh call transport.play
```

没有段落（`sections` 为空）就自己算：副歌通常在第 2 段，`16–24` 小节。

**坑**：
- `loop.set` 的 `b` 是**结束点**，区间是半开的 `[a, b)`。
- 长度 < 1 秒会被拒（`PRECONDITION_FAILED`）。
- `loop.enable` 之前必须 `loop.a/b` 都非空，否则 `PRECONDITION_FAILED`。
- 练习结束 `loop.clear`，否则下次播放会跳回 A 点。

---

## 配方 4：修一条"听不见"的轨

诊断顺序（不要跳）：

```bash
scripts/mcp.sh call state | jq '.tracks[] | select(.token=="midi:…")'
```

| 看到 | 原因 | 修法 |
| --- | --- | --- |
| `hasAudio = false`, `noteCount > 0` | 写了音符没渲染 | `track.render {"track":"midi:…"}` |
| `noteCount = 0` | 没写音符 | `notes.replace …` |
| `isMuted = true` | 被静音 | `track.mix {"mute":false}` |
| `volume = 0` | 音量为 0 | `track.mix {"volume":0.8}` |
| 其他轨 `isSoloed = true` | 有轨在独奏 | 逐条 `track.mix {"solo":false}` |
| 都正常 | 可能被折叠/超出工程长度 | `track.fold {"on":false}`，看音符是否在 0…duration 内 |

`notes.get {"limit":5}` 可以确认音符真在里面以及起始时间。

---

## 配方 5：交付一版混音（带质检）

```bash
scripts/mcp.sh call qc.mix     # 先质检，不合格别导出
scripts/mcp.sh call export.mix # 返回绝对路径
scripts/qc.sh                  # 封装版：阈值不过退出非 0
```

`qc.mix` 返回的关键字段：

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
- 导出会**临时渲染一遍**，比 `qc.mix` 慢；先 QC 再导出能省一次。
- MIDI 轨不参与导出，必须先 `track.render`（`hasAudio = true` 才有声音）。
- 文件落在 App 容器 `Application Support/AgentControl/Exports/`，把返回的绝对路径给用户；
  **不要**用 `cp` 去猜位置。

---

## 配方 6：排查"成片只有伴奏，没有人声"

这是最典型的一次事故。按顺序查：

```bash
scripts/mcp.sh call state | jq '{solo: [.tracks[] | select(.isSoloed) | .token],
                                 muted: [.tracks[] | select(.isMuted) | .token],
                                 noAudio: [.tracks[] | select(.hasAudio == false) | .token],
                                 lead: [.tracks[] | select(.role=="leadVocal") | {token, volume, pan}]}'
```

1. `solo` 非空 → 有轨在独奏，其他全被压掉：逐条 `solo: false`。
2. `muted` 含主唱 → `mute: false`。
3. `noAudio` 含主唱的 MIDI 轨 → `track.render`。
4. 主唱 `volume = 0` → `volume: 1`。
5. 都正常但仍听不到 → `notes.get` 看音符时间是否落在 `0…project.duration` 之外。

导出前永远先看这一条：**导出只乘轨道音量，不乘独奏/静音**（历史事故：某次导出把伴奏乘 0，
成片只剩录音）。所以"导出听起来不对"和"播放听起来不对"可能不是同一个原因 —— 以 `qc.mix` 的
`tracks[].hasSignal` 与 `checks.leadHasSignal` 为准。

---

## 配方 7：从零用一段旋律建一首小样（含风格切换）

`scripts/demo_twinkle.py` 是端到端样例：拿《小星星》当旋律，按风格自动写伴奏、
混音、渲染，最后导出并质检。它替你做了两件最容易出错的事 —— 时间换算（全部由 BPM 推
到 beat 网格）和音域校验（调内三度，不是固定 +4 半音）。

```bash
scripts/demo_twinkle.py --plan                 # 只看编排统计，不连 App
scripts/demo_twinkle.py                        # 轻快流行 100 BPM，四轨
scripts/demo_twinkle.py --style ballad         # 抒情 72 BPM，第四轨换成铺底长音
scripts/demo_twinkle.py --style folk --bpm 126 # 民谣 126 BPM，去掉和声
```

把它当**模板**用，不要当成品：改 `MELODY`（起始拍、时值拍、MIDI）就能换旋律，
改 `CHORDS` 换和声走向，`STYLES` 里加一项就是新风格。

### 编曲轨也能导出（2026-10-22 起）

导出源包括伴奏分轨（stem）、编曲 MIDI 轨（midi）与录音 take。纯编曲工程（空工程 + 几条 MIDI 轨）现在可以正常出混音，但**必须先
`track.render`** —— 导出读的是渲染出来的整曲对齐 WAV，没渲染过的轨不会出现在
导出源里（因此也不会在面板上给你一条点了必然报错的项）。

所以顺序是固定的一句：**写音符 → `track.mix` → `track.render` → `export.mix`**，
少了 render 就报 `this project has nothing to export`。`track.render` 返回
`rendered: true` 只说明这一轨渲染成功，**能导出**要等 `export.mix` 真的返回路径。

导出文件名里带轨道短 id（`...-midi-lead-a7aa-...`），因为四条轨可能都叫「主旋律」，
中文轨名 slug 化之后会撞车；短 id 保证唯一，且同一工程两次导出稳定同名。

---

## 配方 8：换掉某一条轨的声音（取出 → 处理 → 放回 → 撤回）

适用：换鼓、换主唱、把 AI 重新生成的一轨分轨放回去、给一条轨重做 EQ / 降噪。

```bash
# 0 先认轨：token、kind、role、hasAudio
scripts/mcp.sh call track.list | jq '.tracks[] | {token, kind, role, hasAudio, durationSeconds}'

# 1 取出（唯一出口：App 在沙盒里，客户端读不到它的容器）
ID=$(scripts/mcp.sh call track.audio.export '{"track":"drums"}' | jq -r .downloadId)
scripts/mcp.sh download "$ID" /tmp/drums.m4a

# 2 随便怎么处理，产物必须是能解码的音频
ffmpeg -i /tmp/drums.m4a -af 'highpass=f=40,volume=-6dB' -c:a aac -b:a 320k /tmp/drums-2.m4a

# 3 推回容器 → 拿 fileId
FID=$(scripts/mcp.sh upload /tmp/drums-2.m4a | jq -r .fileId)

# 4 先预演（什么都不写），再真换
scripts/mcp.sh call track.audio.replace "{\"track\":\"drums\",\"file\":\"$FID\",\"dryRun\":true}"
scripts/mcp.sh call track.audio.replace "{\"track\":\"drums\",\"file\":\"$FID\",\"confirm\":true}"

# 5 读回：replaced=true，且文件真的换了
ID2=$(scripts/mcp.sh call track.audio.export '{"track":"drums"}' | jq -r .downloadId)
scripts/mcp.sh download "$ID2" /tmp/drums-check.m4a
shasum -a 256 /tmp/drums.m4a /tmp/drums-check.m4a

# 6 反悔（只对分轨有效）
scripts/mcp.sh call track.audio.restore '{"track":"drums"}'
```

**坑**：
- **别试图直接读容器**：`~/Library/Containers/online.c1c1.acapella/…` 在 shell 里是
  `Operation not permitted`。`track.audio.export` + `GET /download` 是唯一的出口，
  `track.audio.replace` 是唯一的入口。
- **口径不用自己补**：落盘一律 44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒。换进来的素材
  采样率/声道/长度都可以不一样，`replace` 会重采样 + 补静音 + 截断。
- **`at` 慎用**：分轨不给 `at` 就是 0 秒对齐（整曲对齐口径）。给了 `at: "9:1"`，
  前 9 秒会变成静音。
- **`fit: "reject"` 会拒长度不符的**：容差 0.25 s（解码取整），但落在容差内的缺口会在
  `warnings` 里说"末尾 X 秒是静音"—— 不要忽略。
- **派生轨不跟随**：换掉 `drums` 后 `Drums Other`（残差轨）仍是旧渲染。
  要一致就重新生成。
- **两类轨语义不同**：分轨 stem 换文件、可 `restore`；录音 take 换掉 = 覆盖（同 App 里重录），
  **没有 restore**；
  纯 MIDI 轨也不能换（没有音频文件），走 `notes.replace` + `track.render`。
- **换完必须重跑 `qc.mix`**：新素材常常更响，`peakGuardCeiling = 0.89`（约 −1 dBFS），
  `peakDbfs` 超过 −0.3 就要用 `track.mix` 的 `volume` 压回来。

---

## 配方 9：MIDI 和弦编配

按和弦生成 MIDI 乐器声部时使用 `choir.options` / `choir.create`；也可用 `notes.replace` 手写 MIDI 乐器音符。
当前不支持人声音色、真声合唱或人声阿卡贝拉编曲。

---

## 配方 10：给工程配一份能跟唱的歌词

歌词是**整首歌一份文本**，不属于任何一条轨；面板在播放器里，存 `<recordID>_lyrics.json`。

```bash
# 0 先看现状：有没有、什么格式、能不能跟唱
scripts/mcp.sh call lyrics.get '{"limit":5}'

# 1 写入（LRC 逐行；时间戳必须 mm:ss.xx —— 分钟两位、小数两到三位）
cat > /tmp/song.lrc <<'LRC'
[ti:小星星]
[00:00.00]一闪一闪亮晶晶
[00:04.00]满天都是小星星
LRC
scripts/mcp.sh call lyrics.set "$(jq -Rs '{text: .}' /tmp/song.lrc)"

# 2 读回：format 必须是 lrc、timedLineCount > 0、plainText = false
scripts/mcp.sh call lyrics.get '{"limit":5}'

# 3 对不上就挪时间轴（不要重发整份词）
scripts/mcp.sh call lyrics.offset '{"by":-0.3}'
```

**改已有歌词**（保时间戳的往返）：

```bash
scripts/mcp.sh call lyrics.get '{"raw":true}' | jq -r .text > /tmp/cur.lrc   # 原格式回吐（含 [ti:]/[offset:]）
# …改几个字…
scripts/mcp.sh call lyrics.set "$(jq -Rs '{text: .}' /tmp/cur.lrc)"
```

**坑**：

- **写进去 ≠ 对上了**。纯文本（没有时间戳）存得进、看得见，但面板不跟随播放、双击不跳转。
  判断只看 `plainText` / `timedLineCount`，不要看 `hasLyrics`。
- **`[0:12]` / `[00:12]` 不是合法 LRC**（缺百分秒）：不报错，整份降级成纯文本，
  方括号原样显示成正文。返回值 `plainText = true` + 一条 warning 就是这个情况。
- **`offset` 省略即归零**：换了一份新词，旧的同步偏移对它没意义。换词时把偏移一起给。
- **歌词只属于当前打开的工程**，整首歌一份。要给别的工程写，先 `project.open`。
- **只挪时间轴用 `lyrics.offset`**（`by` 相对 / `to` 绝对 / `reset`），一次 0.2～0.5 秒。
- 逐词（`[mm:ss.xx]词` 或 `[mm:ss.xx]<mm:ss.xx>词`）能按词高亮；只有逐行也够用，先求对得上。
