---
name: acapella-arranger
description: 用 `acapella` CLI 驱动 macOS 上的 Acapella App——建工程（定 BPM / 拍号 / 调性）、加轨、写音符、**换 MIDI 轨音色（人声元音 / 乐器）**、按界面右键菜单生成真声合唱与 MIDI 合唱、**手写多人阿卡贝拉合唱（SATB 一人一轨）**、调混音与效果、设 AB 循环练习、按小节定位、导出成片并做客观质检。当用户说"建个工程""把这几个声部做出来""给这首歌编合唱/和声""做个阿卡贝拉合唱团""无伴奏合唱""四个人四个声部""生成真声合唱""来个 MIDI 合唱/低音线/琶音""换个音色/换个元音""这段人声换成呜或噢""定个调""分轨听一下""设一个副歌循环""导出一版混音""这段人声放进工程"，或直接要求 AI 操作 Acapella 时使用。Do not use for pure music-theory questions or audio post-production with no project context.
metadata:
  version: "0.5.0"
  requires: acapella 0.5.0+
compatibility: 需要 macOS 14+ 与 Acapella.app；`acapella` 装在 PATH 里（brew tap govo/tap && brew trust govo/tap && brew install acapella），App 设置页「AI 控制」已打开。
allowed-tools: Bash(acapella:*) Bash(${CLAUDE_SKILL_DIR}/scripts/*)
---

# Acapella 编曲与工程操作

你不是在"编辑一个文件"，而是在**遥控一个正在运行的 App**：它是唯一写入者，你只能通过
`acapella` 发命令。App 内存态与磁盘工程由它自己保证一致，你越界（直接改文件/SQLite/JSON）
只会制造分叉。

## 开始任何会话前（3 步，不可跳过）

```bash
acapella doctor     # 1. 连不上就在这里停住
acapella state      # 2. 把它当唯一事实，不要假设任何状态
```

3. 复述计划：要改哪条轨、改什么、预期结果 —— 然后再动手。

`doctor` 失败时**不要**自己 `open -a Acapella`、不要改端口、不要动 token：那是在猜。
请用户打开 App → 设置 → 「AI 控制」→ 打开开关，再重跑。

## 铁律

- **只通过 `acapella` 改东西。** 永远不要读写 App 的工程文件、SQLite、WAV。
- **写完立刻读回。** 写命令的返回值就是读回结果，用它，不要再 `state` 一遍猜。
- **`warnings` 必须看。** 夹取、改名、被忽略的参数都在里面；忽略它下一步就 `NOT_FOUND`。
- **破坏性操作先问人**（删工程 / 删轨 / 覆盖已录 take），拿到同意再加 `--confirm`。
- **不确定就 `--dry-run`。** 它会告诉你将发生什么，且什么都不写。
- **建工程时就把 BPM / 拍号 / 长度 / 调性一次给全。** 空工程的 BPM 是**建时就定死的**，
  事后 `beat set` 会回 `UNSUPPORTED`；`beat analyze` 在空工程上也走不通（没有可分析的音频）。
- **生成合唱前先定调、再复核。** `key set --key C` → `key get` 看 `effective`。
  没定调也能生成，但渲染器会退回逐声部音高推断 —— 这是"和声听着不对"的头号原因。
- **「调性」= 调性轨（`keySections`），不是和弦面板那个「指定调号」。** 后者是另一个字段
  `detected`，只在渲染器取调链里排第 4 顺位。`key set` / `project create --key` 写的都是
  调性轨；判断"调性准不准"看 `hasKeyTrack`、`spans` 与 `effective`，别只看 `detected`。
- **调用生成类命令时它自己会等**（`harmony create` / `choir create` 阻塞到出波形才返回）。
  **不要**再并发连发多条指望"同时生成"：它们是同一条串行队列，并发只会让每条都在排队等。
- **时间用 `bar:beat`**（从 1 起），比秒稳：`17:3` = 第 17 小节第 3 拍。改 BPM 不会错位。
- **一次只改一件事**，改完看返回值里的 `revision` 变了没 —— 没变说明没生效。
- **轨道 token 只信 `track list` / `state`**，别凭名字猜。`@track:"名字"` 只对**MIDI 轨**按名查找，
  重名会报歧义；音频 stem 用固定 token（`vocals` / `drums` / …）。

## 命令地图

全表在 `references/commands.md`（由 `acapella docs` 生成）。**任何命令是否存在，以 `acapella caps` 为准**——文档写着但 `caps` 里没有，一律视为不存在。服务端命令当前 64 条，另有 8 条本地命令（`doctor` `rpc` `upload` `download` `auth set-token/status/clear` `help` `docs` `job wait`）。
日常只用这几组：

| 组 | 代表命令 |
| --- | --- |
| 会话 | `state` `caps` `history` `job get` |
| 工程 | `project list/get/create/open/close/rename/star/delete` |
| 轨道 | `track list/add/get/rename/delete/move/mix/fold/render` |
| 音色 | `instrument list` `track instrument` |
| 音符 | `notes get/replace/patch/analyze` |
| 调性 | `key get/set` |
| 合唱 | `harmony options/create` `choir options/create/voices` |
| 音频 | `upload`（本地）`download`（本地）`take import` `take list/get` |
| 轨道音频 | `track audio export/replace/restore` |
| 走带 | `transport play/pause/stop/seek/position/speed/countin` |
| 循环 | `loop get/set/enable/clear` `section list` |
| 节拍 | `beat get/set/analyze/downbeat` |
| 交付 | `export mix/tracks` `qc mix/notes` |

`acapella rpc <cmd> --flag value` 是逃生门：CLI 还没包的命令可以直接发。

**三条合法的创作路径，都能被读回来**：

| 路径 | 步骤 | 用来做 |
| --- | --- | --- |
| MIDI | `track add --kind midi` → `notes replace` → `track render` | 自己写的声部、编曲 |
| 音频 | `upload` → `take import --track <录音轨>` → `track get` 读回 | AI 生成的成品音频、用户给的样本 |
| 换音 | `track audio export` → 处理 → `upload` → `track audio replace` | 改掉**已有**那一轨的声音（换鼓、换主唱） |
| 合唱 | `key set` → `harmony create` / `choir create` | 从一段人声派生真声合唱 / MIDI 合唱 |
| 阿卡贝拉 | `choir voices` → `track add --kind midi` × N → `notes replace` × N | **多人无伴奏合唱**：一人一声部，音符由你写 |

音频这条路**不能跳步**：`upload` 只把字节搬进容器（不进时间线），`take import` 才写工程。
落盘是整曲对齐的，`--at` 之前补静音，所以 `durationSeconds`（源音频）与 `fileDurationSeconds`（整曲）是两个数。

**「换音」不是「加音」**：`take import` 是往轨上加一遍新的（已有 take 才需 `--confirm` 覆盖），
`track audio replace` 是**把这一轨的声音本身换掉**，连分轨 stem 也能换。
想"改某条轨的音频"就用后者，别绕 `take import` —— 分轨 stem 根本挂不上 take。
取出 → 处理 → 放回 → 反悔，四步闭环见工作流 E。

合唱有**三条路**，先分清用户要哪一种 —— 选错等于没做：

| 用户要的 | 走哪条 | 谁写音符 |
| --- | --- | --- |
| 给主唱加一层和声，丰富一点 | `harmony create`（真声） | 机器渲染音频，你一个音都不写 |
| 按和弦铺一条低音 / 琶音 / 平行线 | `choir create`（模板） | 机器套模板，你只选声部串 |
| **阿卡贝拉合唱团：多人、无伴奏、一人一个声部** | `choir voices` → 手写 N 条 MIDI 轨 | **你写** —— 每个声部每个音 |

前两条走的是**界面上右键菜单的同一个入口**（`enqueueHarmonyGeneration` 那条串行队列），
所以 CLI 建出来的东西与手点出来的一模一样：有音频、有波形、多声部类型落成多条轨。
细节见 `references/harmony.md`。

第三条**没有生成入口**：它不是"让 App 生成合唱"，而是"你按声部编一首合唱"。
所以别对它用 `harmony create`（那是渲染真声音频，你一个音符都没写，用户要的多人合唱没发生），
也别用 `choir create` 连发四次（一条命令只产出一条模板线，四次也只是四条各自独立的陪衬线，
不是互相咬合的织体）。具体做法见工作流 F。

**还不能做的，别假装能做**：
- `fx *` / `midi import` / `midi export`：无此命令（`caps.features.fx` 报 `true` 是旧版自描述错误，以 `caps.commands` 为准）。
- `project import`：需要用户在 App 里选文件（导入成品工程要分离、建记录、算节拍），CLI 走不通。
- 空工程上 `beat set` / `beat analyze`：都不行。BPM 只能在 `project create` 时给。

**读的能力**：`state` / `track list` 给轨的骨架（类型、音符数、有没有音频、是不是空轨）；
`track get` 给具体文件、时长、采样率、take 元数据（起点 / 时长 / trim）；`notes get` 给音符；
`take list` 还给 peak / RMS / 是否削波 —— 写完音频要用它确认"真的有声"，不要靠猜。

## 音色（钢琴卷帘的 timbre）与免费边界

MIDI 轨的音色分两类，共 22 个：**非人声 7 个**（方波 / 正弦 / 三角 / 锯齿 / 钢琴 / 电钢 / 贝斯）、
**人声元音 8 个 × 男女 = 16 个**。一条轨一个音色，改它会**重渲染这条轨**。

```bash
acapella instrument list                                  # 清单：id、是不是人声、当前档位能不能选
acapella track instrument <track> piano                   # 换非人声音色
acapella track instrument <track> ah --voice male         # 人声元音：短名 + 性别（默认女声）
acapella track instrument <track> synth.choirOoh --dry-run
```

| 档位 | 能选的音色 |
| --- | --- |
| 免费 | **全部非人声音色** + 人声里的**「啊」**（`synth.choirAh` / `synth.choirAhMale`） |
| Pro | 16 个人声元音全开（呜 / 噢 / 嗯 / 啊呀 / 咦 / 哦呜 / 嘿 + 啊） |

四条必须记住的口径：

1. **免费用户只能用「啊」唱**。给免费用户编人声声部时写 `--instrument ah`（或干脆用非人声音色），
   别写 `ooh` / `oh` / `ee` —— 会拿到 `LIMIT_REACHED`（`feature: vocal_vowel_pro`），白跑一轮。
2. **已经选过的不退回**。轨道上存着 Pro 元音（付费期选的、别人分享的工程）时
   `track list` 会显示 `instrumentId: "synth.choirOoh"` 且 `instrumentLocked: true` ——
   这条轨**照常出声、照常能写音符、照常能渲染**。`instrumentLocked` 只说"免费档不能重新选"。
   **绝对不要**为了"合规"把它改回「啊」或方波：那是把用户已经编好的东西改坏。
3. **同一个音色再设一次不算换**（`target == current` 放行），所以"重设成它现在的音色"永远是安全的。
   真正被拦的只有"换成**另一个**锁定元音"。
4. **真声合唱轨不能换音色**（`role = vocalHarmony`，内容是音频）：改它会 `PRECONDITION_FAILED`。
   它在卷帘里的音色只作用于参照音符，声音来自主唱移调 —— 要改就去换源轨再 `harmony create`。

不确定档位时先读 `caps.features.instruments`：`freeSelectable` / `lockedForFree` / `keepExisting` 都在里面，
比试错快。

## 读懂 state

```jsonc
{
  "revision": 41,                       // 写操作会 +1；没变 = 没写进去
  "project": { "id": "…", "name": "…", "duration": 214.6, "bpm": 92, "isBlank": false },
  "transport": { "isPlaying": false, "position": { "seconds": 61.2, "bar": "17:1" }, "speed": 1 },
  "loop": { "enabled": false, "a": null, "b": null },
  "beat": { "isFallback": false, "bpm": 92, "beatsPerBar": 4, "source": "auto" },
  "key": { "hasKeyTrack": true, "detected": "C", "effective": "C", "hasExplicit": true,
           "sections": [ { "start": {"seconds":0,"bar":"1:1"}, "key": "C", "source": "user" } ],
           "spans": [ { "start": {"seconds":0,"bar":"1:1"}, "end": {"seconds":214.6,"bar":"54:1"}, "key": "C" } ] },
  "tracks": [
    { "token": "vocals", "kind": "stem", "role": "leadVocal", "hasAudio": true,
      "volume": 1, "pan": 0, "isMuted": false, "isSoloed": false, "noteCount": 0 },
    { "token": "midi:6F1C…", "kind": "midi", "name": "Harmony 3", "hasAudio": true,
      "volume": 0.5, "pan": -0.25, "noteCount": 412, "fx": { "bypassed": false },
      "instrumentId": "synth.choirAh", "instrumentName": "女声和声·啊",
      "vocal": true, "instrumentLocked": false }
  ],
  "sections": [ { "name": "副歌", "start": { "seconds": 61.2, "bar": "17:1" }, "duration": 30.1 } ]
}
```

- `beat.isFallback = true` → 没有可用节拍网格，`bar:beat` 会报 `PRECONDITION_FAILED`。
  两条路：`beat set --bpm 92`（手工给），或 `beat analyze --wait`（让 App 分析）。
  **两条都只对导入工程有效**：空工程（`project.kind = "blank"`）的 BPM 建时定死，
  `beat set` 回 `UNSUPPORTED`、`beat analyze` 回 `PRECONDITION_FAILED`。空工程上 `beat.isFallback`
  正常为 `false` —— 它自带手动网格。
- `key.effective` 是**合唱真正会用的调**（调性轨优先，回落到 `detected`）。
  「调性」指的是 `sections` / `spans` 这条**调性轨**；`detected` 只是和弦面板「指定调号」
  下拉的值，仅在取调链第 4 顺位兜底。判断"调性准不准"看 `hasKeyTrack` / `spans` / `effective`。
- `tracks[].hasAudio = false` 的 MIDI 轨是**幽灵轨**：写了音符但没 `track render`，听不到。
- `tracks[].instrumentId` 是这条轨的音色（落盘值，跟着工程走）；`vocal = true` 表示人声元音；
  `instrumentLocked = true` 表示**当前档位不能再把它选回来**，但轨道照样能用（见「音色与免费边界」）。
- `role` 只有五种，和界面上的轨道种类一一对应：`recording`（录音轨）/ `midi`（MIDI 声部轨）/
  `choir`（MIDI 合唱，生成器产出）/ `vocalHarmony`（真声合唱，内容是音频）/ `take`（TAKE 子轨）。
  **能不能接 take 看 `isRecordingTrack`，不要看 `role`**（真声合唱轨也能挂 take）。
- 分轨工程里 `role = leadVocal` / `vocals` 的是分轨 stem，不是上面这五种 MIDI 轨。

## 工作流 A：从零做一首阿卡贝拉

```bash
acapella project create "Song" --bpm 92 --beats-per-bar 4 --bars 64 --key C   # 返回完整快照
acapella track add "Lead Vocal" --kind recording                      # 录音轨（麦克风，take import 的落点）
acapella track add "Bass"  --kind midi                                # 空白 MIDI 轨（键盘，默认 kind）
acapella track add "Pad"   --kind midi
```

1. **节拍已经在建工程时定了**：`beat get` 只用来核对（`bpm` 是否等于你给的）。
   空工程上 `beat set` 会回 `UNSUPPORTED`（BPM 建时定死），`beat analyze` 也没音频可分析 ——
   所以 `project create` 里那个 `--bpm` / `--beats-per-bar` 必须一次给对。
2. **写声部**：`notes replace --track midi:… --notes @parts.json`（一次写完整段，别一个音一条命令）。
3. **渲染**：所有轨写完后 **一次** `track render --track midi:…`；批量写、一次渲染。
4. **混音**：`track mix --track midi:… --volume -3dB --pan L20`（声像/音量起点见 `references/music.md`）。
5. **质检**：`scripts/qc.sh`（内部跑 `qc mix`，阈值不过就退出非 0）。
6. **交付**：工程本身就是交付物。`acapella export mix` 只是给用户试听的辅助证据，用返回的绝对路径告诉他文件在哪。

## 工作流 B：用户已经给了一份编配（音符表 / 和弦）

- 用户给和弦进行（`C Am F G`）→ `scripts/arrange_from_chords.sh` 直接产出 4 条声部的 notes JSON。
- 用户给音符 JSON → `notes replace`，再 `qc notes --track midi:…` 查音域与重叠。
- 用户给 MIDI 文件 → 这个版本**导不进来**（无 `midi import`）。请用户把音符贴成 JSON，或先在 App 里手动导入。

## 工作流 C：把一段音频放进工程（AI 生成的成品 / 用户给的样本）

```bash
acapella track list                                   # 先找落点：role=recording / role=take 的轨
acapella upload ~/Desktop/lead.wav                    # → fileId
acapella take import --file <fileId> --track <录音轨> --at 9:1
acapella track get <录音轨>                            # 读回：文件名、时长、起点
```

1. **落点**：空项目的每条人声轨（`role = "recording"`）都能接；分轨工程里选主唱 / 已存在的 take 轨。
   目标是已有 take 的轨 = **覆盖那一遍录音**，要加 `--confirm`。
2. **对齐**：整曲对齐落盘，`--at` 决定起点（`--at 1:1` = 0 秒）。音频比工程长会在 `warnings` 里说尾巴放不下。
3. **确认**：`hasAudio = true` 且 `durationSeconds` 与源文件一致（误差 ≤ 0.05s）才算成。
   有声没声看 `take list` 的 `hasSignal` / `peakDbfs`，别靠"返回成功"。

## 工作流 D：从零做一个带合唱的工程（对应用户在界面上手点的顺序）

```bash
# 1 建工程：BPM / 拍号 / 长度 / 调性 一次给全（空工程的 BPM 建时定死，事后改不了）
acapella project create "小星星2" --bpm 100 --beats-per-bar 4 --bars 16 --key C

# 2 音频进轨（等它返回，再往下）
FID=$(acapella upload /private/tmp/lead.m4a | jq -r .fileId)
acapella take import --file "$FID" --track midi:<主唱轨> --at 1:1

# 3 定调，并复核"合唱会按哪个调唱"
acapella key set --key C
acapella key get          # 看 effective / spans / readyForHarmony

# 4 生成合唱（命令自己会等到出波形才返回）
acapella harmony create --source midi:<主唱轨> --type thirdAbove --level 0.6
acapella harmony create --source midi:<主唱轨> --type thirdBelow --level 0.55
acapella choir   create --source midi:<主唱轨> --part bass.quarter
acapella choir   create --source midi:<主唱轨> --part arpeggio.above.eighth

# 5 核对：5 条轨全部 hasAudio = true
acapella state
```

四条硬规矩：

1. **先有音频，再谈合唱**：源轨 `hasAudio = false` 时 `create` 直接 `PRECONDITION_FAILED`。
2. **先定调，再生成**：没定调也能跑，但每声部各自推断调 —— 跑调的第一嫌疑。
   `key set --key C` 写的就是**调性轨**（整曲一段、来源 `user`），它在渲染器取调链里排第一；
   转调歌用 `key set --key G --at 17:1` 加转调点。
3. **串行，不并发**：`create` 内部共用一条串行队列，连着发就是排队；并发发只会互相挡。
4. **验收看 `hasAudio`，不看"返回成功"**：真声合唱轨 `noteCount = 0` 是正常的（它是音频），
   MIDI 合唱轨要 `noteCount > 0`。

完整菜单结构、21 种类型、36 个声部串、调性五级链见 `references/harmony.md`。

## 工作流 E：改某一条轨的音频（换鼓、换主唱、把 AI 重做的一轨放回去）

```bash
acapella track list                                            # 1 先认 token 与 role
acapella track audio export drums --out /tmp/drums.m4a         # 2 取出来（唯一出口）
ffmpeg -i /tmp/drums.m4a -af 'highpass=f=40,volume=-6dB' /tmp/drums-2.m4a
FID=$(acapella upload /tmp/drums-2.m4a | jq -r .fileId)        # 3 推回去
acapella track audio replace drums --file "$FID" --dry-run     # 4 先看会改成什么
acapella track audio replace drums --file "$FID" --confirm     # 5 真换
acapella track audio export drums --out /tmp/drums-check.m4a   # 6 读回：replaced=true
acapella track audio restore drums                             # 7 反悔（分轨专用）
```

1. **先 `export` 再动手。** 它的返回里有 `sampleRate` / `channels` / `durationSeconds` /
   `sourceFile` / `replaced`，替换要对齐的就是这个时长。**不要**自己猜"这一轨多长"。
2. **口径不用你操心，也别自己补零。** 落盘一律 44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒；
   `replace` 会重采样、`--at` 之前补静音、超长截断。
3. **替换写的是新文件**（`<工程>_<轨>_agent.m4a`），原分离文件原地不动 ——
   所以 `restore` 只是把记录里的文件名指回去，不需要重跑分离。
4. **`--confirm` 不能省**，破坏性写操作。先 `--dry-run` 看 `wouldReplace`。
5. **派生轨不跟随。** 换掉 `drums` 之后 `Drums Other`（残差轨）与真声合唱仍是上一次的渲染，
   `warnings` 会点名。要一致就重新生成，别以为"换了鼓，导出就一定是新鼓"。
6. **两类轨换法不同**：分轨 stem 换文件、可 `restore`；录音 take 换掉就是覆盖（同 App 里重录一遍），
   **没有 restore**。真声合唱轨**不能换**（它是从源轨渲染出来的）—— 去换源轨再 `harmony create`。
7. **验收看三件事**：`replaced = true`、`export` 再取一次**文件确实变了**（大小/时长/sha）、
   `qc mix` 的 `peak` / `clipped` 仍过关（新素材常常更响，`peakGuardCeiling = 0.89`）。

## 工作流 F：写一首多人阿卡贝拉（SATB，一人一轨）

**什么时候走这条**：用户说的是「阿卡贝拉合唱团」「无伴奏合唱」「四个人四个声部」「人声乐队」，
或明确要「每个人唱一个声部」。**不是**「给主唱加点和声」（那是工作流 D）。

```bash
acapella choir voices                          # 1 音域表 + 约束（只读，不建轨）
acapella key get                               # 2 调性是编曲前提，没有就 key set
acapella track add --kind midi --name Bass     # 3 一人一轨：四声部 = 四次
acapella track add --kind midi --name Tenor
acapella track add --kind midi --name Alto
acapella track add --kind midi --name Soprano
# 4 每个声部写一份 notes JSON：[{start,duration,pitch,velocity}]，一次写完一条轨
acapella notes replace <Bass>    --notes @bass.json
acapella notes replace <Tenor>   --notes @tenor.json
acapella notes replace <Alto>    --notes @alto.json
acapella notes replace <Soprano> --notes @soprano.json
acapella qc notes                              # 5 音域 / 重叠
acapella qc mix                                # 6 平衡 / 削波
```

硬约束（完整版在 `choir voices` 的 `rules` 里，这里只列最容易犯的）：

1. **一人一轨**。四声部就是四条 MIDI 轨。把整个合唱塞进一条轨 = 音域跨两个八度，
   听起来是合成器垫音，不是四个人。
2. **音域**（`choir voices` 同时给 MIDI 号与音名，直接用）：
   Bass E2–E4、Tenor C3–A4、Alto F3–F5、Soprano C4–C6；大部分音留在舒适区。
3. **间距**：相邻声部不超过八度（T–B 可到十二度）。无伴奏没有乐器填缝，缝一大就露洞。
4. **平行五度 / 八度**：两声部同向连续五度或八度，在裸织体里会糊成一条线，避开。
5. **旋律只归一个声部**（通常 Soprano，男声主唱时 Tenor），其他人不许同度叠。
6. **和声别拖**：一个和弦最多撑两小节。没有乐器维持，长音会塌。
7. **力度当配器用**：内声部（A/T）0.55–0.7，外声部（S/B）0.75–0.9。四条都 0.8 像管风琴。
8. **写形式，不要写循环**。主歌 / 副歌 / 桥段换 voicing；原样复制粘贴正是 `choir create` 干的事。

验收：

- 每条声部轨 `noteCount > 0` 且 `hasAudio = true`（`notes replace` 会自动重渲染，不用再 `track render`）。
- `notes get` 抽查：最高/最低音落在本声部 `range` 内，不是「大概没问题」。
- `qc mix`：`clipped = false`，内声部别跟主唱抢同一中频。

> 免费档每工程的 MIDI 轨数有限，四声部可能装不下。**先看 `caps` 的额度**；
> 装不下就如实告诉用户（升级，或退成二声部），不要在第三条轨上撞 `LIMIT_REACHED`。
>
> 音色同理：免费用户的人声声部只能唱「啊」（`--instrument ah`，女声 / 男声各自一份）。
> 想要四个不同元音的「嘟·哇·哼·啊」效果，先看 `caps.features.instruments`，
> 免费档做不出来就直说，不要一条条撞 `vocal_vowel_pro`。

## 交付前自检（每次都要跑）

```
[ ] state.revision 比开始时大（改动真的生效）
[ ] 每条新轨 hasAudio = true，noteCount > 0（不是幽灵轨）
[ ] 合唱轨：真声合唱 hasAudio = true（noteCount 可以是 0）；MIDI 合唱 noteCount > 0
[ ] key get 的 effective 与用户要求的调一致（不是"大概知道是 C"）
[ ] 写进去的内容能读回（notes get 与写入一致）
[ ] 音频轨：`hasAudio = true` 且 `take list` 的 `hasSignal = true`（不是空文件）
[ ] 换过音的轨：`track audio export` 回来的 `replaced = true`，且文件大小/时长与换之前**不同**
[ ] 换完再跑一次 `qc mix`：peak < −0.3 dBFS（新素材常更响）
[ ] qc mix: peak < -0.3 dBFS 且 clipped = false
[ ] qc mix: 主唱轨 hasSignal = true（不是只剩伴奏）
[ ] notes 音域在 references/music.md 表内（越界会被听出来）
[ ] 阿卡贝拉：每条声部轨 `noteCount > 0`，且 `notes get` 的最高/最低音在该声部 `range` 内
[ ] 阿卡贝拉：相邻声部间距 ≤ 八度（T–B 十二度），没有连续平行五 / 八度
[ ] 音色：改过音色的轨 `track list` 里的 `instrumentId` 就是你要的那一个（免费档别出现锁定元音）
[ ] 音色：轨道原本就有的锁定元音**没被你改回**「啊」（`instrumentLocked` 是状态，不是待修的错）
[ ] 导出文件存在，时长 ≈ project.duration（只在循环里导出时 ≈ b − a）
```

`scripts/qc.sh` 把前四条做成了退出码。

## 反例（这些错最常犯）

- ❌ `cat project.json` / 改 SQLite —— 与内存态分叉，App 一保存就覆盖你的改动。
- ❌ 用秒猜位置（"大概 1:04"）—— 用 `bar:beat`，服务端能对齐。
- ❌ 一次 `notes replace` 写 3000 个音后立刻 `render` 30 条轨 —— 串行渲染会卡住 App 数分钟。
- ❌ 期待"加 5 条和声轨同时生成" —— 生成与渲染都是串行的，按序等。
- ❌ 建完工程才想改 BPM —— 空工程的 BPM 是建时定死的，`beat set` 会回 `UNSUPPORTED`。建之前就问清楚。
- ❌ 只看 `state.key.detected` 就断定"调性对了" —— 用 `key get` 的 `effective`；detected 只是兜底顺位之一。
- ❌ 忽略 `warnings`（"名字重复已改名"）后继续用旧名字寻址 —— 下一步必 `NOT_FOUND`。
- ❌ 把 `track render` 当成"写音符" —— 它只把已有音符渲成音频，不写音符。
- ❌ 空工程里 `project import` —— 它要用户在 App 里选文件（导入成品工程要分离、建记录、算节拍）；自己的音频要走 `upload` + `take import`。
- ❌ 想直接 `ffmpeg -i ~/Library/Containers/online.c1c1.acapella/…/drums.m4a` —— **读不到**（`Operation not permitted`）。
  先用 `track audio export` 让它复制到中转区再下载。
- ❌ 用 `take import` 去"改分轨的鼓" —— 分轨 stem 挂不上 take。改已有音轨的声音只走 `track audio replace`。
- ❌ `cp` 新音频覆盖容器里的分轨文件 / 改记录 JSON 里的 `stemFileNames` —— 与内存态分叉，App 一保存就还原。
- ❌ 对真声合唱轨 `track audio replace` —— 它是从源轨渲染出来的，换源轨再 `harmony create`。
- ❌ 换了鼓就以为导出是新鼓 —— 派生残差轨与真声合唱是旧渲染，看 `warnings`。
- ❌ 用 `harmony create` 交付「阿卡贝拉合唱团」—— 那是对主唱做移调渲染，你一个音符都没写；用户要的多人合唱没有发生。
- ❌ 用 `choir create` 连发四次充当四声部 —— 每条只产出一条模板线（低音 / 琶音 / 平行），四条各自为政，不是互相咬合的织体。
- ❌ 把整个合唱团写进一条 MIDI 轨 —— 音域跨两个八度，听感是合成器垫音；`qc` 看不出来，但人一耳朵就能听出不是四个人。
- ❌ 给免费用户写 `--instrument ooh` / `oh` / `ee` —— 只有「啊」免费；撞 `vocal_vowel_pro` 前先读 `caps.features.instruments`。
- ❌ 看到 `instrumentLocked: true` 就去"修正"它 —— 那是**已选过的 Pro 元音**，退回「啊」等于把用户的编曲改坏。
- ❌ 对 `role = vocalHarmony` 的轨 `track instrument` —— 它是音频，音色改不动（`PRECONDITION_FAILED`）；去换源轨再 `harmony create`。

## 出错时

`references/troubleshooting.md` 有错误码决策树。最快的三条：

- 退出码 3 → App 没监听或 token 不对：`acapella doctor`。
- `NOT_FOUND` → token 过期：`acapella track list` 重新取。
- `PRECONDITION_FAILED` → 缺前置条件（没节拍网格、循环未设）：看返回值里的 `hint`。

## 安装

```bash
brew tap govo/tap && brew trust govo/tap   # Homebrew 6 起第三方 tap 必须先信任
brew install acapella               # 或：把 acapella 二进制放进 PATH
acapella --version                  # 需 0.1.0+，且必须认 auth 子命令
acapella auth set-token <token>     # App → 设置 → 「AI 控制」→ 复制 token
acapella doctor                      # 全绿才继续
```

**凭证只存 `~/.config/acapella/token`，不要试图去读 App 的沙盒容器**（实测 `Operation not permitted`）。

若 `acapella auth` 报 `unknown command`，说明手上的二进制早于凭证改造（旧分发物），
请更新到最新构建——**不要** `--token` 硬塞、不要改端口、不要手动往容器里写文件。

Skill 本身用软链安装（开发时改文件立即生效）：

```bash
ln -sfn /Users/govo/Documents/Work/cursor/acapella_skill/acapella-arranger \
        ~/.workbuddy/skills/acapella-arranger
```
