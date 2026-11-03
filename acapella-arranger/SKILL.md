---
name: acapella-arranger
description: 用 `acapella` CLI 驱动 macOS 上的 Acapella App——建工程（定 BPM / 拍号 / 调性）、加 MIDI 轨、写音符、按和弦编配 MIDI 声部、生成 MIDI 合唱、给工程写入 / 替换 / 对齐歌词（LRC、逐词、纯文本）、调混音与效果、设 AB 循环练习、按小节定位、导出成片并做客观质检。当用户说"建个工程""把这几个声部做出来""按和弦编配""来个 MIDI 合唱/低音线/琶音""定个调""设一个副歌循环""导出一版混音""帮我加歌词/把这首词填进去""歌词对不上/早了慢了""换一份歌词"，或直接要求 AI 操作 Acapella 时使用。当前暂不支持人声音色、真声合唱或人声编曲。本 Skill 不用于纯音乐理论问题或无工程上下文的音频后期。
metadata:
  version: "0.6.0"
  requires: acapella 0.6.0+
compatibility: 需要 macOS 14+ 与 Acapella.app；`acapella` 装在 PATH 里（brew tap govo/tap && brew trust govo/tap && brew install acapella），App 设置页「AI 控制」已打开。
allowed-tools: Bash(acapella:*) Bash(${CLAUDE_SKILL_DIR}/scripts/*)
---

# Acapella MIDI 编曲与工程操作

你不是在"编辑一个文件"，而是在**遥控一个正在运行的 App**：它是唯一写入者，你只能通过
`acapella` 发命令。**每一次取数据、每一次改数据，都必须通过 `acapella` CLI（及其背后的
App 接口）执行，禁止破解、禁止绕过接口、禁止直接读写或修改 App 里的数据**
（工程文件 / SQLite / JSON / WAV 等一律不许碰）。App 内存态与磁盘工程由它自己保证一致，
你越界只会制造分叉。

## 开始任何会话前（3 步，不可跳过）

```bash
acapella doctor     # 1. 连不上就在这里停住
acapella state      # 2. 把它当唯一事实，不要假设任何状态
```

3. 复述计划：要改哪条轨、改什么、预期结果 —— 然后再动手。

`doctor` 失败时**不要**自己 `open -a Acapella`、不要改端口、不要动 token：那是在猜。
请用户打开 App → 设置 → 「AI 控制」→ 打开开关，再重跑。

## 铁律

- **只通过 `acapella` 取数、改数。** 无论读还是写，都只走 CLI 接口，永远不要破解、
  不要绕过接口、不要直接读写 App 的工程文件、SQLite、WAV。
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
- **调用生成类命令时它自己会等**（`choir create` 阻塞到生成完成才返回）。
  **不要**再并发连发多条指望"同时生成"：它们是同一条串行队列，并发只会让每条都在排队等。
- **时间用 `bar:beat`**（从 1 起），比秒稳：`17:3` = 第 17 小节第 3 拍。改 BPM 不会错位。
- **一次只改一件事**，改完看返回值里的 `revision` 变了没 —— 没变说明没生效。
- **轨道 token 只信 `track list` / `state`**，别凭名字猜。`@track:"名字"` 只对**MIDI 轨**按名查找，
  重名会报歧义；音频 stem 用固定 token（`vocals` / `drums` / …）。

## 命令地图

全表在 `references/commands.md`（由 `acapella docs` 生成）。**任何命令是否存在，以 `acapella caps` 为准**——文档写着但 `caps` 里没有，一律视为不存在。服务端命令当前 68 条，另有 8 条本地命令（`doctor` `rpc` `upload` `download` `auth set-token/status/clear` `help` `docs` `job wait`）。
日常只用这几组：

| 组 | 代表命令 |
| --- | --- |
| 会话 | `state` `caps` `history` `job get` |
| 工程 | `project list/get/create/open/close/rename/star/delete` |
| 轨道 | `track list/add/get/rename/delete/move/mix/fold/render` |
| 音符 | `notes get/replace/patch/analyze` |
| 歌词 | `lyrics get/set/offset/clear` |
| 调性 | `key get/set` |
| MIDI 合唱 | `choir options/create` |
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
| MIDI 编配 | `track add --kind midi` → `notes replace` | 写乐器声部与和弦编配 |

音频这条路**不能跳步**：`upload` 只把字节搬进容器（不进时间线），`take import` 才写工程。
落盘是整曲对齐的，`--at` 之前补静音，所以 `durationSeconds`（源音频）与 `fileDurationSeconds`（整曲）是两个数。

**「换音」不是「加音」**：`take import` 是往轨上加一遍新的（已有 take 才需 `--confirm` 覆盖），
`track audio replace` 是**把这一轨的声音本身换掉**，连分轨 stem 也能换。
想"改某条轨的音频"就用后者，别绕 `take import` —— 分轨 stem 根本挂不上 take。
取出 → 处理 → 放回 → 反悔，四步闭环见工作流 E。

当前不支持人声音色、真声合唱或人声合唱团编曲。MIDI 乐器编配和音乐理论知识仍可用；不要把乐器轨描述成歌声。

合唱有**两类乐器编配**：

| 用户要的 | 走哪条 | 谁写音符 |
| --- | --- | --- |
| 按和弦铺一条低音 / 琶音 / 平行线 | `choir create`（MIDI 模板） | 机器套模板，你只选声部串 |

细节见 `references/harmony.md`。不要将 MIDI 模板声部称为人声或真声合唱。

**还不能做的，别假装能做**：
- `fx *` / `midi import` / `midi export`：无此命令（`caps.features.fx` 报 `true` 是旧版自描述错误，以 `caps.commands` 为准）。
- `project import`：需要用户在 App 里选文件（导入成品工程要分离、建记录、算节拍），CLI 走不通。
- 空工程上 `beat set` / `beat analyze`：都不行。BPM 只能在 `project create` 时给。

**读的能力**：`state` / `track list` 给轨的骨架（类型、音符数、有没有音频、是不是空轨）；
`track get` 给具体文件、时长、采样率、take 元数据（起点 / 时长 / trim）；`notes get` 给音符；
`take list` 还给 peak / RMS / 是否削波 —— 写完音频要用它确认"真的有声"，不要靠猜。

## 歌词（整首歌一份文本，不属于任何一条轨）

```bash
acapella lyrics get --limit 40                 # 有没有、什么格式、能不能跟唱、偏移多少
acapella lyrics set --text @song.lrc           # 写入 / 替换整份（LRC / 逐词 / 纯文本，自动识别）
acapella lyrics set --text @song.lrc --offset -0.3
acapella lyrics offset --by -0.3               # 只挪时间轴，不重写文本
acapella lyrics clear                          # 删掉这份词（轨 / 音频 / MIDI 都不动）
```

四条硬口径：

1. **「写进去了」不等于「对上了」**。只有带时间戳的写法（`[mm:ss.xx]这一行` 逐行、
   `[mm:ss.xx]这 [mm:ss.xx]是` 标准逐词、`[mm:ss.xx]<mm:ss.xx>这` 增强逐词）面板才会高亮跟随播放。
   纯文本存得进、看得见，但**不跟唱**。判断看返回值的 `plainText` 与 `timedLineCount`，
   不要只看 `hasLyrics`。
2. **时间戳必须是 `mm:ss.xx`**（分钟两位、小数两到三位）。写成 `[0:12]` / `[00:12]` 不会报错，
   而是**整份降级成纯文本** —— 方括号会原样显示成正文。这种情况返回 `plainText = true`
   外加一条 warning，看到就当成失败重发。
3. **歌词属于当前打开的工程，整首歌一份**。没有"哪条轨的歌词"这回事 —— 要写别的工程先
   `project open`（`lyrics set` 对非当前工程直接报 `PRECONDITION_FAILED`）。
4. **只挪时间轴别重发文本**。用户说"歌词慢了半拍"→ `lyrics offset --by -0.3`，一次挪 0.2～0.5 秒。
   `set` 会把偏移**重置**（`--offset` 省略即归零）：换了一份新词就顺手把偏移一起给，
   否则新词整体跑偏而 `lines` 看着完全正常。

`lyrics get --raw` 返回的 `text` 就是 `lyrics set` 能吃回去的原格式文本：改几个字再写回，
时间戳一个不丢。要"逐句改写 / 补一段"就走这条，别照着 `lines[]` 自己重拼 ——
那份时间戳是取整过的，往返几次只会越对越歪。

## 音色与人声支持

钢琴卷帘目前只开放乐器音色，不支持人声音色。MCP 和 CLI 不提供人声音色的查询或修改能力；
旧工程中已保存的音色数据仅作为兼容数据，不要通过编排工作流新增或切换人声音色。
目前也不支持真声合唱或人声阿卡贝拉编曲。音乐理论、和弦分析以及 MIDI 乐器编配仍可使用。

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
  "lyrics": { "hasLyrics": true, "format": "lrc", "plainText": false,
              "lineCount": 42, "timedLineCount": 42, "offset": -0.3, "panelVisible": false },
  "tracks": [
    { "token": "vocals", "kind": "stem", "role": "leadVocal", "hasAudio": true,
      "volume": 1, "pan": 0, "isMuted": false, "isSoloed": false, "noteCount": 0 },
    { "token": "midi:6F1C…", "kind": "midi", "name": "Harmony 3", "hasAudio": true,
      "volume": 0.5, "pan": -0.25, "noteCount": 412, "fx": { "bypassed": false },
      "noteCount": 412 }
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
- `lyrics.plainText = true` 表示这份词**没有时间轴**：面板显示得出，但不跟随播放、
  双击不跳转。要跟唱就得重发一份带 `[mm:ss.xx]` 的词（见「歌词」一节）。
  `lyrics.offset` 是同步偏移（正数 = 词比声音晚），只调它用 `lyrics offset`。
- `role` 区分轨道种类，如 `recording`、`midi`、`choir` 与 `take`。能否接 take 看 `isRecordingTrack`。
- 分轨工程里 `role = leadVocal` / `vocals` 的是分轨 stem，不是上面这五种 MIDI 轨。

## 人声支持状态

目前不支持人声音色、真声合唱或人声阿卡贝拉编曲。若用户提出此类需求，说明功能暂不可用；
仍可协助音乐理论、和弦分析与 MIDI 乐器编配。

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

## 工作流 D：MIDI 合唱生成

当前不支持人声合唱生成。`choir create` 生成的是 MIDI 乐器声部，可用于按和弦铺低音、琶音或平行线；
不要使用已撤下的真声 `harmony create` 能力。相关命令以 `acapella caps` 实际返回为准。

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
5. **派生轨不跟随。** 换掉 `drums` 之后 `Drums Other`（残差轨）与派生轨仍是上一次的渲染，
   `warnings` 会点名。要一致就重新生成，别以为"换了鼓，导出就一定是新鼓"。
6. **两类轨换法不同**：分轨 stem 换文件、可 `restore`；录音 take 换掉就是覆盖（同 App 里重录一遍），
   **没有 restore**。派生轨音频来自源轨渲染，替换后检查 `warnings`。
7. **验收看三件事**：`replaced = true`、`export` 再取一次**文件确实变了**（大小/时长/sha）、
   `qc mix` 的 `peak` / `clipped` 仍过关（新素材常常更响，`peakGuardCeiling = 0.89`）。

## 人声支持状态

目前不支持人声音色、真声合唱或人声阿卡贝拉编曲。若用户提出此类需求，说明功能暂不可用；
仍可协助音乐理论、和弦分析与 MIDI 乐器编配。

## 交付前自检（每次都要跑）

```
[ ] state.revision 比开始时大（改动真的生效）
[ ] 每条新轨 hasAudio = true，noteCount > 0（不是幽灵轨）
[ ] key get 的 effective 与用户要求的调一致（不是"大概知道是 C"）
[ ] 写进去的内容能读回（notes get 与写入一致）
[ ] 音频轨：`hasAudio = true` 且 `take list` 的 `hasSignal = true`（不是空文件）
[ ] 换过音的轨：`track audio export` 回来的 `replaced = true`，且文件大小/时长与换之前**不同**
[ ] 换完再跑一次 `qc mix`：peak < −0.3 dBFS（新素材常更响）
[ ] qc mix: peak < -0.3 dBFS 且 clipped = false
[ ] qc mix: 主唱轨 hasSignal = true（不是只剩伴奏）
[ ] notes 音域在 references/music.md 表内（越界会被听出来）
[ ] 歌词：`lyrics get` 的 `plainText = false` 且 `timedLineCount` 等于应有的行数（能跟唱）
[ ] 歌词：末行 `end` 没超出 `project.duration`（超了会有一条 warning，别忽略）
[ ] 歌词：用户说"对不上"时用的是 `lyrics offset`，没有把整份词重发一遍
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
- ❌ 换了鼓就以为导出是新鼓 —— 派生残差轨与真声合唱是旧渲染，看 `warnings`。
- ❌ 写完歌词就宣布"词配好了" —— 纯文本（`plainText = true`）不跟唱；看 `timedLineCount`。
- ❌ 拿 `[0:12]词` / `[00:12]词` 当 LRC 写 —— 缺百分秒会被整份降级成纯文本，方括号原样显示。
- ❌ 为了挪 0.3 秒把整份歌词重发一遍 —— `lyrics offset --by -0.3` 就够，重发还可能把时间戳改歪。

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
