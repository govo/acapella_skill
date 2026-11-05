# MCP 工具全表

> 数据源是服务端的 `tools/list`（`scripts/check-tools.sh` 用来校验本文与实现是否一致）。
> 当前 65 个工具，其中 3 个是 DEBUG 构建专用的调试工具，正式版不出现。
> **文档写着但 `tools/list` 里没有的，一律视为不存在。**

调用形状永远是这一句：

```jsonc
tools/call  { "name": "track.mix", "arguments": { "track": "drums", "volume": "-3dB" } }
```

命令行/脚本里跑（没有原生工具调用时）：

```bash
scripts/mcp.sh call track.mix '{"track":"drums","volume":"-3dB"}'
```

---

## 会话

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `state` | — | 当前工程的完整快照（工程 / 走带 / 循环 / 节拍 / 轨道 / 分段） |
| `revision` | — | 当前 revision（只有写操作会推进） |
| `caps` | — | 能力表：工具 + 参数 + 权限档位（机器可读） |
| `ping` | — | 心跳：确认 App 在监听，返回 revision |
| `history` | `since?` int | 最近的 agent 操作记录（谁改了什么） |
| `job.get` | `id?` string | 异步任务状态（给 id 查一个，不给列出全部） |

**`state`**
> AI 的第一步：把它当作唯一事实，不要假设任何工程状态。

**`caps`**
> 让 AI 自己发现能力；比读本文更准。

## 工程

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `project.list` | `query?` `limit?` | 作品库列表 |
| `project.get` | `project?` id 或名字前缀 | 单个工程（打开中的那个会带轨道） |
| `project.create` | `name` `bpm?` `beatsPerBar?` `bars?` `duration?` `key?` `mode?` | 新建空工程并打开（返回完整快照） |
| `project.open` | `project?` | 打开一个工程（会切走界面）并返回快照 |
| `project.close` | — | 关闭当前工程，回到列表 |
| `project.rename` | `project` `name` | 改工程名 |
| `project.star` | `project` `star?` bool | 收藏 / 取消收藏 |
| `project.delete` | `project` `confirm` bool | 删除工程（破坏性：`confirm: true`） |
| `project.import` | `file` | 导入音频/视频成新工程（未实现：需要用户在 App 里选文件） |

**`project.create`**
> 建出来就是空工程，只有一条待录的录音轨；加轨用 `track.add` 的
> `kind: "recording" | "midi"`，两种轨分开建（分轨模型不存在）。长度给 `bars` 或
> `duration` 二选一，夹取会出现在 `warnings` 里 —— 不要忽略。
> `key` 是**建议必填**：写的是**调性轨首段**（不是「指定调号」下拉那个字段）。
> 空工程没有音频，调性没法事后推断；不填就只能等生成合唱时逐声部猜，
> 猜错了整条和声都会跑偏。合法写法 C / F# / Bb / Am。

**`project.import`**
> 和 `POST /upload` 不是一回事：上传解决的是"把一段音频放进**已打开**的工程"
> （`take.import`），导入工程要跑分离、建记录、算节拍，入口必须是用户亲手选的那个文件。
> 硬塞上传的字节等于绕过分离流程造一个半成品工程，所以这里明确报 UNSUPPORTED。

## 轨道

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `track.list` | — | 轨道列表（时间线顺序、类型、混音状态、音符数、有没有音频） |
| `track.get` | `track` | 这条轨里到底是什么：音频文件、时长、采样率、take 元数据 |
| `track.add` | `kind` `name?` `after?` | 加轨：`recording`（录音轨）或 `midi`（空白 MIDI 轨），空工程才两种都能加 |
| `track.rename` | `track` `name` | 改轨名 |
| `track.delete` | `track` `confirm` | 删除轨道（破坏性） |
| `track.move` | `track` `to?` `after?` | 移动轨道到某个位置或某条轨之后 |
| `track.mix` | `track` `volume?` `pan?` `mute?` `solo?` | 调一条轨的音量 / 声像 / 静音 / 独奏 |
| `track.fold` | `track` `on?` bool | 折叠 / 展开轨道（只影响显示） |
| `track.render` | `track` | 把 MIDI 轨渲染成音频（写完音符统一渲染一次） |

**`track.get`**
> 读的是播放引擎真正调度的那个文件。分轨给源文件；MIDI / 合唱 / take 给整曲对齐的
> 渲染 WAV。音频类字段在 `audio` 里，take 轨另外带 `take`（起点、时长、归属）。

**`track.add`**
> `kind: "recording"` 建**录音轨**（轨道头是麦克风，`take.import` / 录音的落点）；
> `kind: "midi"` 建**空白 MIDI 轨**（轨道头是键盘，用 `notes.replace` 画音符）。
> 两种轨只在空工程里能加：导入工程只有分轨 + 由分轨派生的轨。
> 已有的轨不会被这条工具改掉：真声合唱（`vocalHarmony`）、MIDI 合唱（`choir`）
> 以及它们下面的 TAKE 子轨照旧。想分辨一条轨是哪一种，读 `track.list` 的 `role`
> （recording / midi / choir / vocalHarmony / take）与 `isRecordingTrack`
> （能不能接 take）。别靠名字猜。

**`track.mix`**
> 音量写 `0.7` 或 `-3dB` 都行；声像写 `L30` / `R15` / `-0.3` / `0`。
> 注意 solo 会让其他轨在导出里变静音 —— 返回值里会带 warning。

## 音频（取出 / 放回）

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `track.audio.export` | `track` | 把一条轨的音频取回本机（返回 `downloadId`，再用 `GET /download/<id>` 取字节） |
| `track.audio.replace` | `track` `file` `at?` `fit?` `confirm?` | 用上传的音频替换一条轨的内容（对齐到整曲时间轴） |
| `track.audio.restore` | `track` | 撤回上一次对分轨的音频替换（原分离文件一直没动） |
| `take.import` | `file` `track` `at?` `name?` `confirm?` | 把上传的音频写成整曲对齐 WAV，挂到某条录音轨上 |
| `take.list` | `track?` | 工程里所有 take：挂在哪条轨、从第几秒开始、多长、有没有声 |
| `take.get` | `track` | 读一条 take（给 take 的 token），或一条宿主轨下面的全部 take |

**`track.audio.export`**
> 这是唯一能把工程里那段声音取出来的通道：App 在沙盒里，你读不到它的容器，
> 所以由 App 复制一份到中转区，返回 `downloadId`，你再用 `GET /download/<id>` 把字节取走。
> 分轨给的是分离产物原文件（AAC 320k，44.1 kHz 立体声）；
> take / 录音轨给的是整曲对齐的 WAV。落地后可以直接用 ffmpeg / sox / 模型处理，
> 处理完用 `track.audio.replace` 放回去。
> 下载区的 id 只留 6 小时，过期返回 404。

**`track.audio.replace`**
> 先 `POST /upload` 拿 fileId，再用这个工具把它变成**这条轨的声音** ——
> 替换主唱、替换鼓、把 AI 重新生成的一轨分轨放回去，都走这里。
> 落盘口径与分离产物一致：44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒；
> `at` 之前与工程末尾之后补静音，比工程长会在 warnings 里说尾巴放不下。
> `fit: "reject"` 改成"长度对不上就报错"，适合严格对齐的场景。
> **必须带 `confirm: true`**（原来的声音不再播放）。分轨的原文件不会被覆盖：
> 新音频写的是 `<工程>_<轨>_agent.m4a`，随时可以 `track.audio.restore` 指回去。
> 换完要重新听一遍就 `track.audio.export` + `qc.mix`。

**`track.audio.restore`**
> 只对分轨（stem）有效。分轨替换写的是新文件，原文件原地保留，
> 所以"还原"只是把记录里的文件名指回去 —— 不需要重新跑分离。
> 录音 take 换掉就是换掉了（和 App 里重录一遍同语义），这个工具会明确报 UNSUPPORTED，
> 别去猜"是不是没生效"。

**`POST /upload`（不是工具，是字节通道）**
> 传的是**文件本身的字节**，不是路径，也不 base64。`POST /upload?name=lead.wav`，
> body 就是文件内容，头里带同一个 `Authorization: Bearer`。
> App 收下后会立刻解码校验：解不开的文件当场报 BAD_REQUEST（而不是等到 `take.import` 才失败）。
> 返回值的 `fileId` 是下一步的入参。上传只把字节搬进容器，**不进时间线** ——
> 真正落进工程要接着调 `take.import`。上传区保留 24 小时，过期后 fileId 失效，重新上传即可。

**`take.import`**
> `track` 给宿主轨：空项目的人声轨（写进它自己）、分轨主唱、或任意 MIDI 轨。
> **一条目标轨只有一条 take**：宿主上已经有 take 时直接覆盖那一条（整条音频替换），
> 这时必须带 `confirm: true`；没有才新建。给一条**已有 take** 的 token 效果相同。
> 落盘口径与录音完全一致：44.1k 立体声、第 0 帧 = 歌曲 0 秒，`at` 之前的空白由
> 静音补齐。返回的 `durationSeconds` 是**源音频**长度，`fileDurationSeconds` 是落盘
> 后的整曲长度——两个数不要混。
> 例：`POST /upload` → `take.import {file: "<id>", track: "midi:…", at: "9:1"}`

**`take.list`**
> 给 `track` 就只看那条宿主轨下面的。`audio` 里是峰值 / RMS / 是否削波。

## 音符

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `notes.get` | `track` `from?` `to?` `limit?` `offset?` | 读一条轨的音符（可给时间窗） |
| `notes.replace` | `track` `notes` array | 整条轨替换音符（会自动重渲染） |
| `notes.patch` | `track` `transpose?` `quantize?` `velocity?` `insert?` `delete?` `from?` `to?` | 增量改音符：移调 / 量化 / 改力度 / 插入 / 删除 |
| `notes.analyze` | `track` | 音符统计 + 问题（音域、同音重叠、覆盖率） |

**`notes.replace`**
> 音符是 `[{start, duration, pitch, velocity}]`，**直接作为 JSON 数组放进 `notes`**
> （没有 `@file` 这种写法；文件在客户端读好再塞进来）。
> start 是**位置**：bar:beat（1:2 = 第 1 小节第 2 拍）或秒。
> duration 是**长度**：bar:beat 含义不同 —— 1:2 = 1 小节 + 2 拍（4/4、120BPM 下 3 秒）；
> 纯拍数写 beat:2 或 2beats，秒写 0.5。
> pitch 接受 C4 / F#3 / 60，velocity 接受 0.8 或 102。
> 批量写完只渲染一次，不要逐条渲染。

## 歌词

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `lyrics.get` | `limit?` `skip?` `raw?` | 读工程歌词：格式、行数、同步偏移、逐行文本（分页） |
| `lyrics.set` | `text` `offset?` | 写入/替换整份歌词（LRC、逐词或纯文本，格式自动识别） |
| `lyrics.offset` | `by?` `to?` `reset?` | 整体挪歌词时间轴（不重写文本） |
| `lyrics.clear` | — | 删掉这份歌词（只删文本，轨 / 音频 / MIDI 都不动） |

**`lyrics.get`**
> `plainText = true` 表示这份词**没有时间轴**：面板能显示，但不跟随播放、不能双击跳转。
> 判断"能不能跟唱"看 `timedLineCount`，不要只看 `hasLyrics`。
> `format` 是写入时识别出来的那一种（lrc / wordStandard / wordEnhanced / plainText）。
> `raw: true` 额外返回 `text`：那就是 `lyrics.set` 能吃回去的原格式文本，
> 改几个字再写回不会丢时间戳。

**`lyrics.set`**
> `text` 吃**文本本身**（整份歌词的字符串）。
> 写法按顺序识别：增强逐词 `[00:12.34]<00:12.34>这` → 标准逐词 `[00:12.34]这 [00:12.56]是`
> → 逐行 `[00:12.34]这一行`；完全没有时间戳就是纯文本（能看，不跟唱）。
> 时间戳必须是 `mm:ss.xx`（分钟两位、小数两到三位）。写成 `[0:12]` / `[00:12]`
> 不会报错，而是**整份降级成纯文本**，方括号原样显示成正文 ——
> 返回值里 `plainText = true` 再加一条 warning，就是这种情况。
> `offset` 是全局同步偏移（秒，正数 = 歌词晚一点），**省略即归零**：
> 换了一份新词，旧偏移对它没有意义。只是挪时间轴不用重发文本，用 `lyrics.offset`。
> 歌词属于**当前打开的工程**，整首歌只有一份（没有"哪条轨的歌词"这回事）。

**`lyrics.offset`**
> 三选一：`by` 相对挪（负数 = 歌词提前）、`to` 绝对偏移、`reset: true` 归零。
> 返回值里 `offset.total` 是**实际生效**的偏移（文件自带 `[offset:]` + 你调的 `offset.user`）。
> 「歌词比声音慢了半拍」就是 `by: -0.3` 这类。一次挪 0.2～0.5 秒，不要一次挪两秒。

**`lyrics.clear`**
> 歌词可以重新贴，所以不需要 `confirm`。删掉的是文本 + 记录上的文件名，工程内容不受影响。

## 走带

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `transport.play` | — | 开始播放 |
| `transport.pause` | — | 暂停 |
| `transport.stop` | — | 暂停并回到 0 |
| `transport.seek` | `to` | 跳转到某个时间 |
| `transport.position` | — | 当前播放位置与状态 |
| `transport.speed` | `value` number | 播放速度（0.5…1.5） |
| `transport.countin` | `on?` bool | 预备拍开关 |

**`transport.seek`**
> `to` 写 12.5 / 1:23.4 / 17:3 / tick:169920 / start / end 都行。

## 循环

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `loop.get` | — | AB 循环状态（解析后的范围、有效性、命中分段） |
| `loop.set` | `a` `b` `enable?` | 设置 AB 范围（自动排序、夹取、最短 1 秒） |
| `loop.enable` | `on?` bool | 开关 AB 循环（不改范围） |
| `loop.clear` | — | 清空 AB 范围并关掉循环 |
| `section.list` | — | 练习分段列表（标题、范围、锁定、是否命中） |

**`loop.set`**
> 夹取与排序会出现在 warnings 里 —— AI 必须看，否则会以为设成了它想要的范围。

## 节拍

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `beat.get` | — | BPM / 拍号 / 置信度 / 网格来源 |
| `beat.set` | `bpm?` `beatsPerBar?` | 手设 BPM 与拍号（切到手动网格） |
| `beat.analyze` | — | 自动节拍分析（异步：返回 jobId） |
| `beat.downbeat` | `at?` `current?` | 把小节线锚到某个时间（或播放头） |

**`beat.set`**
> 空工程的 BPM 在创建时定死，这里会返回 UNSUPPORTED —— 那是刻意的。

**`beat.analyze`**
> 异步：先拿 `jobId`，再 `job.get` 轮询。脚本里循环等它变成 `done`。

## 调性

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `key.get` | — | 当前调性轨：逐段主调 + 调式 / 生效值 / 来源（user 还是 inferred） |
| `key.set` | `key` `mode?` `at?` | 指定调性（写调性轨；整曲，或在某个时间点加转调） |

**`key.get`**
> `hasKeyTrack` / `sections` / `spans` 才是「调性」—— 调性轨上的分段。
> `effective` 是渲染器会用的那个调（调性轨优先，回落到 `detected`，与渲染器同口径）。
> `detected` 只登记「指定调号」下拉的值，仅供对照，别拿它当调性。
> `hasExplicit = false` = 调性轨还没有人手动指定过，此时 effective 多半来自推断。

**`key.set`**
> 写的是**调性轨**（`sections` / `spans`），不是和弦面板那个「指定调号」下拉
> （那个字段是 `detected`）。两者是两份数据，优先级也不同：渲染器取调时
> 调性轨排第一，`detected` 只排第四。
> 调性 = **主调 + 调式**：`key` 给主音（C / F# / Bb / Am），`mode` 给调式
> （major / naturalMinor / harmonicMinor / dorian / phrygian / lydian / mixolydian / locrian）。
> 省略 `mode` 时按调名后缀解释：`Am` → 小调、`C` → 大调。
> 省略 `at` = 整曲首段（0 秒、来源 `user`）；给 `at` = 在该处加转调点再选调
> （等价界面「加转调点」→「选主调」→「选调式」三步）。
> 非法调名当场拒绝；调性轨被锁时会返回 PRECONDITION_FAILED。

## 合唱

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `choir.options` | — | MIDI 合唱的全部声部串（bass.quarter / arpeggio.below.eighth …） |
| `choir.create` | `source` `part` | 生成 MIDI 合唱轨（等同右键 MIDI Choir） |

**`choir.create`**
> 声部串必须来自 `choir.options`（与菜单项一一对应）；同样会等到渲染完成。

## 导出与质检

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `export.mix` | `loopOnly?` `pitchShift?` `volumes?` | 导出一个混音文件（分轨 + 编曲 MIDI + 和声 + take 都在里面） |
| `export.tracks` | `tracks?` list `video?` `takeVideo?` `loopOnly?` `pitchShift?` `volumes?` | 分轨导出（一条轨一个文件） |
| `qc.mix` | — | 混音客观质检：峰值 / RMS / 削波 / 静音段 / 每轨有无信号 |
| `qc.notes` | `track` | 音符质检：音域、同音重叠、覆盖空洞 |

**`export.mix`**
> 文件落在 App 容器的 Application Support/AgentControl/Exports/ 里，
> 返回值带绝对路径。编曲 MIDI 轨要先 `track.render` 才会进导出（读的是渲染 WAV）。

**`qc.mix`**
> 交付前必跑。它不给主观评价，只给数（不做假 LUFS）。

## 调试（仅 DEBUG 构建）

| 工具 | 参数 | 作用 |
| --- | --- | --- |
| `debug.dumpExampleRecords` | — | 导出内置样例工程的记录信息 |
| `debug.onboarding` | `action` | 重置 / 跳到引导的某一步 |
| `debug.reidentifySampleRecords` | `song` | 重跑样例工程的分轨识别 |

> 正式版 `tools/list` 里不会出现。别在给用户的方案里依赖它们。

---

## 请求级参数（每个工具都能带）

这三个不是业务参数，是**请求信封上的开关**：出现在 `arguments` 里，
由服务端剥出来用，handler 看不到它们。

| 参数 | 类型 | 作用 |
| --- | --- | --- |
| `dryRun` | bool | 只解析与校验，不写入；返回值说明将发生什么 |
| `ifRevision` | int | 乐观并发；与当前 revision 不符 → `CONFLICT` |
| `idempotencyKey` | string | 同一个键重放不会二次生效（重试安全） |

另外 `confirm: true` 是**个别破坏性工具的业务参数**（删工程 / 删轨 / 覆盖 take /
`track.audio.replace`），不是全局开关 —— 别把它当信封字段用。

`scripts/mcp.sh call <tool> '<json>' --dry-run` 会自动帮你加上 `dryRun`。

---

## 时间怎么写

| 写法 | 含义 |
| --- | --- |
| `17.5` | 秒 |
| `1:04` / `1:04.5` | 分:秒 |
| `17:3` | **小节:拍**（都从 1 起；推荐给 AI 用） |
| `tick:960` | 绝对 tick（PPQ 960） |
| `start` / `end` | 工程首尾 |

写合唱、循环、段落时**优先用 `bar:beat`** —— 它跟着速度走，改 BPM 不会错位。

**`start` 与 `duration` 的 `bar:beat` 不是一回事**：`start` 是位置（`1:2` = 第 1 小节
第 2 拍），`duration` 是长度（`1:2` = 1 小节 + 2 拍；4/4、120BPM 下 3 秒）。
纯拍数写 `beat:2` / `2beats`，纯秒写 `0.5`。按位置算长度会让 `1:1` 变成 0 秒。

单位（`-3dB`、`L20`、`C4`）一律原样传字符串，服务端换算；不要自己换成数字。

---

## 怎么指一条轨

| token | 例子 | 说明 |
| --- | --- | --- |
| `midi:<uuid>` | `midi:6F1C…` | MIDI / 合唱轨 |
| stem 名 | `vocals` `drums` `bass` `other` `leadVocal` | 分轨工程里的固定轨 |
| `@track:"名字"` | `@track:"Lead Vocal 1"` | 按 **MIDI 轨名** 找；重名报 `BAD_REQUEST`。音频 stem 用上面的固定 token |

**唯一可靠的 token 来源是 `track.list` / `state`** —— 不要凭印象拼。

---

## 音频怎么进工程（三步，不能跳）

```jsonc
// 1) 裸字节推进容器（不是工具，是旁路通道）
POST /upload?name=lead.wav        // body = 文件字节，头带 Bearer → {"fileId": "…"}

// 2) 落进时间线
tools/call name=take.import
  { "file": "<fileId>", "track": "midi:<录音轨>", "at": "1:1" }

// 3) 读回
tools/call name=track.get   { "track": "<录音轨>" }
```

为什么不能直接给路径：App 在沙盒里，读不到你本机的任意路径。
`/upload` 只把字节搬进容器（**不进时间线**），`take.import` 才写工程。
落盘是**整曲对齐**的（第 0 帧 = 歌曲 0 秒），`at` 之前补静音 —— 这是播放与导出不错位的前提。
`durationSeconds` = 源音频长度；`fileDurationSeconds` = 落盘后的整曲长度，两个数不要混。

命令行里就是：

```bash
scripts/mcp.sh upload ~/Desktop/lead.wav          # → fileId
scripts/mcp.sh call take.import '{"file":"<fileId>","track":"midi:…","at":"1:1"}'
```

## 一条轨的音频怎么改（取出 → 改 → 放回）

```bash
scripts/mcp.sh call track.audio.export '{"track":"vocals"}'      # → downloadId
scripts/mcp.sh download <downloadId> ./vocals.m4a                # 取字节
ffmpeg -i ./vocals.m4a -af 'volume=-3dB' ./vocals-fixed.m4a      # 随便怎么处理
FID=$(scripts/mcp.sh upload ./vocals-fixed.m4a | jq -r .fileId)
scripts/mcp.sh call track.audio.replace "{\"track\":\"vocals\",\"file\":\"$FID\",\"confirm\":true}"
scripts/mcp.sh call track.audio.restore '{"track":"vocals"}'      # 反悔了，回原版
```

为什么必须走这条：客户端读不到 App 的沙盒容器，`export` 的产物由 App 复制到中转区、
再经 `GET /download/<id>` 发给你；想直接 `ffmpeg` 处理容器里那个文件是不可能的。
`replace` 落盘是 44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒（与分离产物同口径），
分轨的原文件不会被覆盖，所以 `restore` 只是把记录指回去。
录音 take 换掉就是换掉了（与界面重录同一语义），没有 restore。

## 写多条 MIDI 声部（编曲）

```jsonc
tools/call name=track.add       { "name": "Bass", "kind": "midi" }   // 一条声部一轨
tools/call name=notes.replace   { "track": "midi:…", "notes": [ … ] } // 每声部一次，自动重渲染
tools/call name=qc.notes        { "track": "midi:…" }
tools/call name=qc.mix
```

`choir.create` 是按和弦**生成**一条模板线（声部串来自 `choir.options`），不需要你写音符；
要自己写声部就加 MIDI 轨再 `notes.replace`，两条路可以混用。
当前不提供人声音色与真声合唱工具。

---

## 错误怎么读

工具失败时**不是** HTTP 错误，而是 `result.isError = true`，信封里带：

```jsonc
{
  "ok": false,
  "revision": 41,
  "error": {
    "code": "PRECONDITION_FAILED",       // 机器判据
    "message": "blank project's tempo is fixed when it is created",
    "hint": "call `project.create` with the bpm you want"   // 下一步动作，照做
  }
}
```

`hint` 是服务端特意写的下一步，比任何猜测都准。错误码含义与处置见
`references/troubleshooting.md`。

三种失败要分清：

| 现象 | 是什么 | 怎么办 |
| --- | --- | --- |
| JSON-RPC `error`（`-32601` / `-32602`） | 方法名或工具名不对、参数结构不对 | 调 `tools/list` 对照；`-32602` 的 `data.hint` 会点名 |
| `result.isError = true` + `error.code` | 业务拒绝（前置条件 / 权限 / 版本边界） | 按 `hint` 补条件，别重试同一个调用 |
| HTTP 401 / 连不上 | token 不对，或 App 没开 / 开关没开 | 重新复制 token；见 SKILL「先确认通道」 |

`scripts/mcp.sh` 的退出码：`0` 成功 · `1` 工具返回 ok=false · `2` 用法/JSON-RPC 错 ·
`3` 连不上或没 token · `4` CONFLICT。
