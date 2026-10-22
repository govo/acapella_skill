---
name: acapella-arranger
description: 用 `acapella` CLI 驱动 macOS 上的 Acapella App——建工程、加轨、写音符、编阿卡贝拉和声、调混音与效果、设 AB 循环练习、按小节定位、导出成片并做客观质检。当用户说"建个工程""把这几个声部做出来""给这首歌编合唱/和声""分轨听一下""设一个副歌循环""导出一版混音""这段人声放进工程"，或直接要求 AI 操作 Acapella 时使用。Do not use for pure music-theory questions or audio post-production with no project context.
metadata:
  version: "0.1.0"
  requires: acapella 0.1.0+
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
- **时间用 `bar:beat`**（从 1 起），比秒稳：`17:3` = 第 17 小节第 3 拍。改 BPM 不会错位。
- **一次只改一件事**，改完看返回值里的 `revision` 变了没 —— 没变说明没生效。
- **轨道 token 只信 `track list` / `state`**，别凭名字猜。`@track:"名字"` 只对**MIDI 轨**按名查找，
  重名会报歧义；音频 stem 用固定 token（`vocals` / `drums` / …）。

## 命令地图

全表在 `references/commands.md`（由 `acapella docs` 生成）。**任何命令是否存在，以 `acapella caps` 为准**——文档写着但 `caps` 里没有，一律视为不存在。服务端命令当前 51 条，另有本地命令（`doctor` `rpc` `upload` `help` `docs` `job wait`）。
日常只用这几组：

| 组 | 代表命令 |
| --- | --- |
| 会话 | `state` `caps` `history` `job get` |
| 工程 | `project list/get/create/open/close/rename/star/delete` |
| 轨道 | `track list/add/get/rename/delete/move/mix/fold/render` |
| 音符 | `notes get/replace/patch/analyze` |
| 音频 | `upload`（本地）`take import` `take list/get` |
| 走带 | `transport play/pause/stop/seek/position/speed/countin` |
| 循环 | `loop get/set/enable/clear` `section list` |
| 节拍 | `beat get/set/analyze/downbeat` |
| 交付 | `export mix/tracks` `qc mix/notes` |

`acapella rpc <cmd> --flag value` 是逃生门：CLI 还没包的命令可以直接发。

**两条合法的创作路径，两条都能被读回来**：

| 路径 | 三步 | 用来做 |
| --- | --- | --- |
| MIDI | `track add --kind midi` → `notes replace` → `track render` | 写声部、和声、编曲 |
| 音频 | `upload` → `take import --track <录音轨>` → `track get` 读回 | AI 生成的成品音频、用户给的样本 |

音频这条路**不能跳步**：`upload` 只把字节搬进容器（不进时间线），`take import` 才写工程。
落盘是整曲对齐的，`--at` 之前补静音，所以 `durationSeconds`（源音频）与 `fileDurationSeconds`（整曲）是两个数。

**还不能做的，别假装能做**：
- `harmony *` / `fx *` / `midi import`：无此命令。（`caps.features` 若出现 `"fx": true`，是旧版自描述错误，以 `caps.commands` 为准。）
- `project import`：需要用户在 App 里选文件（导入成品工程要分离、建记录、算节拍），CLI 走不通。

**读的能力**：`state` / `track list` 给轨的骨架（类型、音符数、有没有音频、是不是空轨）；
`track get` 给具体文件、时长、采样率、take 元数据（起点 / 时长 / trim）；`notes get` 给音符；
`take list` 还给 peak / RMS / 是否削波 —— 写完音频要用它确认"真的有声"，不要靠猜。

## 读懂 state

```jsonc
{
  "revision": 41,                       // 写操作会 +1；没变 = 没写进去
  "project": { "id": "…", "name": "…", "duration": 214.6, "bpm": 92, "isBlank": false },
  "transport": { "isPlaying": false, "position": { "seconds": 61.2, "bar": "17:1" }, "speed": 1 },
  "loop": { "enabled": false, "a": null, "b": null },
  "beat": { "isFallback": false, "bpm": 92, "beatsPerBar": 4, "source": "auto" },
  "tracks": [
    { "token": "vocals", "kind": "stem", "role": "leadVocal", "hasAudio": true,
      "volume": 1, "pan": 0, "isMuted": false, "isSoloed": false, "noteCount": 0 },
    { "token": "midi:6F1C…", "kind": "midi", "name": "Harmony 3", "hasAudio": true,
      "volume": 0.5, "pan": -0.25, "noteCount": 412, "fx": { "bypassed": false } }
  ],
  "sections": [ { "name": "副歌", "start": { "seconds": 61.2, "bar": "17:1" }, "duration": 30.1 } ]
}
```

- `beat.isFallback = true` → 没有可用节拍网格，`bar:beat` 会报 `PRECONDITION_FAILED`。
  两条路：`beat set --bpm 92`（手工给），或 `beat analyze --wait`（让 App 分析）。
- `tracks[].hasAudio = false` 的 MIDI 轨是**幽灵轨**：写了音符但没 `track render`，听不到。
- `role` 决定这条 stem 是不是主唱（`leadVocal` / `vocals`），混音和 QC 都看它。

## 工作流 A：从零做一首阿卡贝拉

```bash
acapella project create "Song" --bpm 92 --beats-per-bar 4 --bars 64   # 返回完整快照
acapella track add "Lead Vocal" --kind vocal                          # 空工程可加人声(录音)轨
acapella track add "Bass"  --kind midi                                # 空工程同样能加 MIDI 轨（默认 kind）
acapella track add "Pad"   --kind midi
```

1. **定节拍**：`beat get` → `isFallback` 就 `beat set --bpm 92 --beats-per-bar 4`。
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

## 交付前自检（每次都要跑）

```
[ ] state.revision 比开始时大（改动真的生效）
[ ] 每条新轨 hasAudio = true，noteCount > 0（不是幽灵轨）
[ ] 写进去的内容能读回（notes get 与写入一致）
[ ] 音频轨：`hasAudio = true` 且 `take list` 的 `hasSignal = true`（不是空文件）
[ ] qc mix: peak < -0.3 dBFS 且 clipped = false
[ ] qc mix: 主唱轨 hasSignal = true（不是只剩伴奏）
[ ] notes 音域在 references/music.md 表内（越界会被听出来）
[ ] 导出文件存在，时长 ≈ project.duration（只在循环里导出时 ≈ b − a）
```

`scripts/qc.sh` 把前四条做成了退出码。

## 反例（这些错最常犯）

- ❌ `cat project.json` / 改 SQLite —— 与内存态分叉，App 一保存就覆盖你的改动。
- ❌ 用秒猜位置（"大概 1:04"）—— 用 `bar:beat`，服务端能对齐。
- ❌ 一次 `notes replace` 写 3000 个音后立刻 `render` 30 条轨 —— 串行渲染会卡住 App 数分钟。
- ❌ 期待"加 5 条和声轨同时生成" —— 生成与渲染都是串行的，按序等。
- ❌ 忽略 `warnings`（"名字重复已改名"）后继续用旧名字寻址 —— 下一步必 `NOT_FOUND`。
- ❌ 把 `track render` 当成"写音符" —— 它只把已有音符渲成音频，不写音符。
- ❌ 空工程里 `project import` —— 它要用户在 App 里选文件（导入成品工程要分离、建记录、算节拍）；自己的音频要走 `upload` + `take import`。

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
