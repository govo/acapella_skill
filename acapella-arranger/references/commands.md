# `acapella` CLI — 命令全表

由 `acapella docs` 从 CLI 自己的命令表生成（v0.5.2，协议 1）。**不要手改**：改 CLI 的命令注册表，再跑 `scripts/gen-commands.sh`。

共 76 条命令。

## 会话

| 命令 | 作用 |
| --- | --- |
| `state` | 当前工程的完整快照（工程 / 走带 / 循环 / 节拍 / 轨道 / 分段） |
| `revision` | 当前 revision（只有写操作会推进） |
| `caps [--compact]` | 能力表：所有命令 + 参数 + 权限档位（机器可读） |
| `ping` | 心跳：确认 App 在监听，返回 revision |
| `history [--since <revision>]` | 最近的 agent 操作记录（谁改了什么） |
| `job get [<id>]` | 异步任务状态（给 id 查一个，不给列出全部） |

**`state`**
> AI 的第一步：把它当作唯一事实，不要假设任何工程状态。

**`caps`**
> 用来生成文档或让 AI 自己发现命令；比读 help 更准。

## 工程

| 命令 | 作用 |
| --- | --- |
| `project list [--query <text>] [--limit 200]` | 作品库列表 |
| `project get [<id\|name>]` | 单个工程（打开中的那个会带轨道） |
| `project create <name> --bpm 92 --beats-per-bar 4 --bars 64 --key C` | 新建空工程并打开（返回完整快照） |
| `project open [<id\|name>]` | 打开一个工程（会切走界面）并返回快照 |
| `project close` | 关闭当前工程，回到列表 |
| `project rename <id\|name> <new-name>` | 改工程名 |
| `project star [<id\|name>] [--star off]` | 收藏 / 取消收藏 |
| `project delete <id\|name> --confirm` | 删除工程（破坏性：需要 own 档 + --confirm） |
| `project import <file>` | 导入音频/视频成新工程（未实现：需要用户在 App 里选文件） |

**`project create`**
> 建出来就是空工程，只有一条待录的录音轨；加轨用 `track add --kind recording|midi`，
> 两种轨分开建（分轨模型不存在）。长度给 --bars 或 --duration 二选一，
> 夹取会出现在 warnings 里 —— 不要忽略。
> `--key` 是**建议必填**：写的是**调性轨首段**（不是「指定调号」下拉那个字段）。
> 空工程没有音频，调性没法事后推断；不填就只能等生成合唱时逐声部猜，
> 猜错了整条和声都会跑偏。合法写法 C / F# / Bb / Am。

**`project import`**
> 和 `upload` 不是一回事：上传解决的是"把一段音频放进**已打开**的工程"（`take import`），
> 导入工程要跑分离、建记录、算节拍，入口必须是用户亲手选的那个文件。
> 硬塞上传的字节等于绕过分离流程造一个半成品工程，所以这里明确报 UNSUPPORTED。

## 轨道

| 命令 | 作用 |
| --- | --- |
| `track list` | 轨道列表（时间线顺序、类型、混音状态、音符数、有没有音频） |
| `track get <track>` | 这条轨里到底是什么：音频文件、时长、采样率、take 元数据 |
| `track add [<name>] [--kind recording\|midi] [--after <track>]` | 加轨：recording（录音轨）或 midi（空白 MIDI 轨），空工程才两种都能加 |
| `track rename <track> <new-name>` | 改轨名 |
| `track delete <track> --confirm` | 删除轨道（破坏性：需要 --confirm） |
| `track move <track> [--to 3] [--after <track>]` | 移动轨道到某个位置或某条轨之后 |
| `track mix <track> [--volume -3dB] [--pan L20] [--mute on] [--solo on]` | 调一条轨的音量 / 声像 / 静音 / 独奏 |
| `track fold <track> [on\|off]` | 折叠 / 展开轨道（只影响显示） |
| `track render <track>` | 把 MIDI 轨渲染成音频（写完音符统一渲染一次） |
| `track instrument <track> <instrument> [--voice male]` | 换 MIDI 轨的音色（免费档：非人声全放开 + 人声只能用「啊」） |

**`track get`**
> 读的是播放引擎真正调度的那个文件。分轨给源文件；MIDI / 合唱 / take 给整曲对齐的
> 渲染 WAV。音频类字段在 `audio` 里，take 轨另外带 `take`（起点、时长、归属）。

**`track add`**
> `--kind recording` 建**录音轨**（轨道头是麦克风，`take import` / 录音的落点）；
> `--kind midi` 建**空白 MIDI 轨**（轨道头是键盘，用 `notes replace` 画音符）。
> 两种轨只在空工程里能加：导入工程只有分轨 + 由分轨派生的轨。
> 已有的轨不会被这条命令改掉：真声合唱（`vocalHarmony`）、MIDI 合唱（`choir`）
> 以及它们下面的 TAKE 子轨照旧。想分辨一条轨是哪一种，读 `track list` 的 `role`
> （recording / midi / choir / vocalHarmony / take）与 `isRecordingTrack`
> （能不能接 take）。别靠名字猜。

**`track mix`**
> 音量写 0.7 或 -3dB 都行；声像写 L30 / R15 / -0.3 / 0。
> 注意 solo 会让其他轨在导出里变静音 —— 返回值里会带 warning。

**`track instrument`**
> 写完整 id（`synth.piano`）、去掉 `synth.` 的简写（`piano` / `choir.ooh`），
> 或元音短名（`ah` / `ooh` / `oh` / `mm` / `aya` / `ee` / `oohoh` / `hey`）。
> 元音短名默认女声，`--voice male` 换男声。清单见 `acapella instrument list`。
> 会**重渲染这条轨**（换音色就是换声音），音符不动。
> 免费档只允许：任意非人声音色 + 人声的「啊」。选别的元音会收到 `LIMIT_REACHED`
> （`feature: vocal_vowel_pro`）。已经存着 Pro 元音的轨道不会被这条命令改回「啊」。

## 音频

| 命令 | 作用 |
| --- | --- |
| `track audio export <track> [--out <file>]` | 把一条轨的音频取回本机（AI 拿去处理），默认落在当前目录 |
| `track audio replace <track> --file <fileId> [--at 1:1] [--fit pad\|reject] [--confirm]` | 用上传的音频替换一条轨的内容（对齐到整曲时间轴） |
| `track audio restore <track>` | 撤回上一次对分轨的音频替换（原分离文件一直没动） |
| `upload <file>` | 把本地音频文件推进 App 容器，返回 fileId（给 take import 用） |
| `take import --file <fileId> --track <track> [--at 1:1] [--name "主唱 1"]` | 把上传的音频写成整曲对齐 WAV，挂到某条录音轨上 |
| `take list [--track <host>]` | 工程里所有 take：挂在哪条轨、从第几秒开始、多长、有没有声 |
| `take get <track>` | 读一条 take（给 take 的 token），或一条宿主轨下面的全部 take |

**`track audio export`**
> 这是唯一能把工程里那段声音取出来的通道：App 在沙盒里，CLI 读不到它的容器，
> 所以由 App 复制一份到中转区，CLI 再用 `GET /download/<id>` 把字节取走。
> `--out` 默认是当前目录 + App 建议的文件名（`<工程名>-<轨名>.m4a`）。
> 分轨给的是分离产物原文件（AAC 320k，44.1 kHz 立体声）；
> take / 录音轨给的是整曲对齐的 WAV。落地后可以直接用 ffmpeg / sox / 模型处理，
> 处理完用 `track audio replace` 放回去。

**`track audio replace`**
> 先 `acapella upload <file>` 拿 fileId，再用这条命令把它变成**这条轨的声音** ——
> 替换主唱、替换鼓、把 AI 重新生成的一轨分轨放回去，都走这里。
> 落盘口径与分离产物一致：44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒；
> `--at` 之前与工程末尾之后补静音，比工程长会在 warnings 里说尾巴放不下。
> `--fit reject` 改成"长度对不上就报错"，适合严格对齐的场景。
> **必须带 `--confirm`**（原来的声音不再播放）。分轨的原文件不会被覆盖：
> 新音频写的是 `<工程>_<轨>_agent.m4a`，随时可以 `track audio restore` 指回去。
> 换完要重新听一遍就 `track audio export` + `qc mix`。

**`track audio restore`**
> 只对分轨（stem）有效。分轨替换写的是新文件，原文件原地保留，
> 所以"还原"只是把记录里的文件名指回去 —— 不需要重新跑分离。
> 录音 take 换掉就是换掉了（和 App 里重录一遍同语义），这条命令会明确报 UNSUPPORTED，
> 别去猜"是不是没生效"。

**`upload`**
> 传的是**文件本身的字节**，不是路径。App 收下后会立刻解码校验：解不开的文件当场报
> BAD_REQUEST（而不是等到 take import 才失败）。返回值里的 `fileId` 是下一步的入参。
> 上传只把字节搬进容器，**不进时间线**——真正落进工程要接着跑 take import。
> 上传区保留 24 小时，过期后 fileId 失效，重新上传即可。

**`take import`**
> `--track` 给宿主轨：空项目的人声轨（写进它自己）、分轨主唱、或任意 MIDI 轨。
> **一条目标轨只有一条 take**：宿主上已经有 take 时直接覆盖那一条（整条音频替换），
> 这时必须加 --confirm；没有才新建。给一条**已有 take** 的 token 效果相同。
> 落盘口径与录音完全一致：44.1k 立体声、第 0 帧 = 歌曲 0 秒，`--at` 之前的空白由
> 静音补齐。返回的 `durationSeconds` 是**源音频**长度，`fileDurationSeconds` 是落盘
> 后的整曲长度——两个数不要混。
> 例：`acapella upload ~/Desktop/lead.wav` → `acapella take import --file <id> --track midi:… --at 9:1`

**`take list`**
> 给 `--track` 就只看那条宿主轨下面的。`audio` 里是峰值 / RMS / 是否削波。

## 音符

| 命令 | 作用 |
| --- | --- |
| `notes get <track> [--from 17:1] [--to 25:1] [--limit 500]` | 读一条轨的音符（可给时间窗） |
| `notes replace <track> --notes @parts.json` | 整条轨替换音符（会自动重渲染） |
| `notes patch <track> [--transpose 2] [--quantize 0.25] [--velocity 0.8] [--insert @add.json] [--delete @ids.json]` | 增量改音符：移调 / 量化 / 改力度 / 插入 / 删除 |
| `notes analyze <track>` | 音符统计 + 问题（音域、同音重叠、覆盖率） |

**`notes replace`**
> 音符是 [{start, duration, pitch, velocity}]。
> start 是**位置**：bar:beat（1:2 = 第 1 小节第 2 拍）或秒。
> duration 是**长度**：bar:beat 含义不同 —— 1:2 = 1 小节 + 2 拍（4/4、120BPM 下 3 秒）；
> 纯拍数写 beat:2 或 2beats，秒写 0.5。
> pitch 接受 C4 / F#3 / 60，velocity 接受 0.8 或 102。
> 批量写完只渲染一次，不要逐条渲染。

## 音色

| 命令 | 作用 |
| --- | --- |
| `instrument list` | 音色清单：id / 名称 / 是不是人声 / 当前档位能不能选 |

**`instrument list`**
> 23 个音色分两类：
> - **非人声**（方波 / 正弦 / 三角 / 锯齿 / 钢琴 / 电钢 / 贝斯）：免费全放开；
> - **人声元音**（啊 / 呜 / 噢 / 嗯 / 啊呀 / 咦 / 哦呜 / 嘿，男女各一份）：共 16 个，
>   免费档只能用**啊**（`synth.choirAh` / `synth.choirAhMale`）。
> 返回里 `freeTier` 是"免费档能不能选"，`selectable` 是"你当前这个档位能不能选"。
> 两者都为 false 时别硬写：换成非人声音色，或 `--instrument ah`。
> `keepExistingVowel: true` 说的是另一件事：轨道上**已经存着**的 Pro 元音
> （付费期选的 / 别人分享的工程）**不会被回退**，照旧出声、照旧能写音符。
> 不要为了"合规"把它改回「啊」—— 那是把用户的编曲改坏。

## 歌词

| 命令 | 作用 |
| --- | --- |
| `lyrics get [--limit 200] [--skip 0] [--raw]` | 读工程歌词：格式、行数、同步偏移、逐行文本（分页） |
| `lyrics set --text @song.lrc [--offset -0.3]` | 写入/替换整份歌词（LRC、逐词或纯文本，格式自动识别） |
| `lyrics offset [--by -0.3] [--to 0.5] [--reset]` | 整体挪歌词时间轴（不重写文本） |
| `lyrics clear` | 删掉这份歌词（只删文本，轨 / 音频 / MIDI 都不动） |

**`lyrics get`**
> `plainText = true` 表示这份词**没有时间轴**：面板能显示，但不跟随播放、不能双击跳转。
> 判断"能不能跟唱"看 `timedLineCount`，不要只看 `hasLyrics`。
> `format` 是写入时识别出来的那一种（lrc / wordStandard / wordEnhanced / plainText）。
> `--raw` 额外返回 `text`：那就是 `lyrics set` 能吃回去的原格式文本，
> 改几个字再写回不会丢时间戳。

**`lyrics set`**
> `--text` 吃**文本本身**：`@song.lrc` 读文件，`--text "$(cat song.lrc)"` 直接给内容。
> 写法按顺序识别：增强逐词 `[00:12.34]<00:12.34>这` → 标准逐词 `[00:12.34]这 [00:12.56]是`
> → 逐行 `[00:12.34]这一行`；完全没有时间戳就是纯文本（能看，不跟唱）。
> 时间戳必须是 `mm:ss.xx`（分钟两位、小数两到三位）。写成 `[0:12]` / `[00:12]`
> 不会报错，而是**整份降级成纯文本**，方括号原样显示成正文 ——
> 返回值里 `plainText = true` 再加一条 warning，就是这种情况。
> `--offset` 是全局同步偏移（秒，正数 = 歌词晚一点），**省略即归零**：
> 换了一份新词，旧偏移对它没有意义。只是挪时间轴不用重发文本，用 `lyrics offset`。
> 歌词属于**当前打开的工程**，整首歌只有一份（没有"哪条轨的歌词"这回事）。

**`lyrics offset`**
> 三选一：`--by` 相对挪（负数 = 歌词提前）、`--to` 绝对偏移、`--reset` 归零。
> 返回值里 `offset.total` 是**实际生效**的偏移（文件自带 `[offset:]` + 你调的 `offset.user`）。
> 「歌词比声音慢了半拍」就是 `--by -0.3` 这类。一次挪 0.2～0.5 秒，不要一次挪两秒。

**`lyrics clear`**
> 歌词可以重新贴，所以不需要 `--confirm`。删掉的是文本 + 记录上的文件名，工程内容不受影响。

## 走带

| 命令 | 作用 |
| --- | --- |
| `transport play` | 开始播放 |
| `transport pause` | 暂停 |
| `transport stop` | 暂停并回到 0 |
| `transport seek <time>` | 跳转到某个时间 |
| `transport position` | 当前播放位置与状态 |
| `transport speed <value>` | 播放速度（0.5…1.5） |
| `transport countin [on\|off]` | 预备拍开关 |

**`transport seek`**
> time 写 12.5 / 1:23.4 / 17:3 / tick:169920 / start / end 都行。

## 循环

| 命令 | 作用 |
| --- | --- |
| `loop get` | AB 循环状态（解析后的范围、有效性、命中分段） |
| `loop set <a> <b> [--enable on]` | 设置 AB 范围（自动排序、夹取、最短 1 秒） |
| `loop enable [on\|off]` | 开关 AB 循环（不改范围） |
| `loop clear` | 清空 AB 范围并关掉循环 |
| `section list` | 练习分段列表（标题、范围、锁定、是否命中） |

**`loop set`**
> 夹取与排序会出现在 warnings 里 —— AI 必须看，否则会以为设成了它想要的范围。

## 节拍

| 命令 | 作用 |
| --- | --- |
| `beat get` | BPM / 拍号 / 置信度 / 网格来源 |
| `beat set [--bpm 92] [--beats-per-bar 4]` | 手设 BPM 与拍号（切到手动网格） |
| `beat analyze [--wait]` | 自动节拍分析（异步：返回 jobId） |
| `beat downbeat [<time>] [--current]` | 把小节线锚到某个时间（或播放头） |

**`beat set`**
> 空工程的 BPM 在创建时定死，这里会返回 UNSUPPORTED —— 那是刻意的。

**`beat analyze`**
> 加 --wait 就轮询到结束再返回，脚本里更好用。

## 调性

| 命令 | 作用 |
| --- | --- |
| `key get` | 当前调性轨：逐段主调 + 调式 / 生效值 / 来源（user 还是 inferred） |
| `key set --key D [--mode dorian] [--at 17:1]` | 指定调性（写调性轨；整曲，或在某个时间点加转调） |

**`key get`**
> `hasKeyTrack` / `sections` / `spans` 才是「调性」—— 调性轨上的分段。
> `effective` 是渲染器会用的那个调（调性轨优先，回落到 `detected`，与渲染器同口径）。
> `detected` 只登记「指定调号」下拉的值，仅供对照，别拿它当调性。
> `hasExplicit = false` = 调性轨还没有人手动指定过，此时 effective 多半来自推断。

**`key set`**
> 写的是**调性轨**（`sections` / `spans`），不是和弦面板那个「指定调号」下拉
> （那个字段是 `detected`）。两者是两份数据，优先级也不同：渲染器取调时
> 调性轨排第一，`detected` 只排第四。
> 调性 = **主调 + 调式**：`--key` 给主音（C / F# / Bb / Am），`--mode` 给调式
> （major / naturalMinor / harmonicMinor / dorian / phrygian / lydian / mixolydian / locrian）。
> 省略 `--mode` 时按调名后缀解释：`Am` → 小调、`C` → 大调。
> 省略 `--at` = 整曲首段（0 秒、来源 `user`）；给 `--at` = 在该处加转调点再选调
> （等价界面「加转调点」→「选主调」→「选调式」三步）。
> 非法调名当场拒绝；调性轨被锁时会返回 PRECONDITION_FAILED。

## 合唱

| 命令 | 作用 |
| --- | --- |
| `harmony options` | 真声合唱的全部类型（取值 / 名称 / 声部数） |
| `harmony create --source <track> --type thirdAbove [--level 0.6]` | 从某条轨生成真声合唱（等同右键 Vocal Harmony） |
| `choir options` | MIDI 合唱的全部声部串（bass.quarter / arpeggio.below.eighth …） |
| `choir create --source <track> --part bass.quarter` | 生成 MIDI 合唱轨（等同右键 MIDI Choir） |
| `choir voices` | 多人阿卡贝拉的四声部音域表与编曲约束（只读，不生成） |

**`harmony options`**
> 先查再建：类型既可用名字（thirdAbove）也可用数字（2），重名与大小写都不敏感。

**`harmony create`**
> 多声部类型会落成多条轨（如 vocalStack4 → 4 条）。命令会等到队列跑空才返回，
> 返回值里的 created[] 就是本次新建的轨（含 hasAudio / noteCount）。

**`choir create`**
> 声部串必须来自 `choir options`（与菜单项一一对应）；同样会等到渲染完成。

**`choir voices`**
> 这条不给工程加任何东西，只回答"怎么写一首无伴奏合唱"：
> SATB 四个声部的可写音域 / 舒适区 / 角色，以及声部间距、平行五八度、
> 力度配比这些约束。
> 什么时候用它：用户要的是「阿卡贝拉合唱团 / 无伴奏合唱 / 多人合唱」，
> 即**你自己按声部写 MIDI**、一人一轨。不是 `harmony create`
> （那是渲染真声音频，你一个音符都不用写），也不是 `choir create`
> （那是按和弦铺一条模板图案，只有一条线）。
> 落地是 `track add --kind midi` × N + 每个声部一次 `notes replace`。

## 导出

| 命令 | 作用 |
| --- | --- |
| `export mix [--loop-only] [--pitch-shift] [--volumes off]` | 导出一个混音文件（分轨 + 编曲 MIDI + 和声 + take 都在里面） |
| `export tracks [all\|token,token] [--video] [--take-video] [--loop-only]` | 分轨导出（一条轨一个文件） |
| `qc mix` | 混音客观质检：峰值 / RMS / 削波 / 静音段 / 每轨有无信号 |
| `qc notes <track>` | 音符质检：音域、同音重叠、覆盖空洞 |

**`export mix`**
> 文件落在 App 容器的 Application Support/AgentControl/Exports/ 里，
> 返回值带绝对路径。编曲 MIDI 轨要先 `track render` 才会进导出（读的是渲染 WAV）。

**`qc mix`**
> 交付前必跑。它不给主观评价，只给数（不做假 LUFS）。

## 本地

| 命令 | 作用 |
| --- | --- |
| `auth set-token <token>` | 保存 App 里显示的 token（一次配置，之后免交互） |
| `auth status` | 看当前用的是哪一份凭证（文件 / 环境变量） |
| `auth clear` | 删掉保存的 token |
| `doctor [--launch]` | 体检：App 在不在、token 能不能读、协议版本对不对 |
| `job wait <id> [--timeout 600]` | 等一个异步任务跑完（轮询 job.get） |
| `rpc <cmd> [--any-arg value …]` | 直接发一条 RPC（CLI 还没跟上命令表时的逃生门） |
| `help [command]` | 看帮助 |
| `docs [--out <file>]` | 把全部命令渲染成 Markdown（skill 的命令表由它生成） |

**`auth set-token`**
> 在 App 的 设置 → AI 控制 里复制 token，粘到这里。写入 ~/.config/acapella/token（0600）。
> 凭证归 CLI 自己，不需要（也不允许）读 App 的沙盒容器。
> 非交互场景（CI、AI agent）用环境变量 ACAPELLA_AGENT_TOKEN 覆盖更省事，
> 它优先于这里保存的文件。用 `acapella auth status` 看当前用的是哪一份。

**`auth status`**
> 只报告凭证来源和长度，不打印 token 本身。

**`doctor`**
> 连不上时先跑这个。它按顺序检查：token 文件 → 端口 → /health → 协议版本 → 权限档位，
> 第一个失败的那一步就是答案。--launch 会在未监听时尝试拉起 App。

**`rpc`**
> 例：acapella rpc track.color --track midi:... --color red

**`docs`**
> 不需要 App 在跑：数据源是 CLI 自己的命令表，所以命令一改，文档跟着变。
> 发布前跑 `scripts/gen-commands.sh` 覆盖 skill 的 references/commands.md。

## 全局选项

| 选项 | 含义 |
| --- | --- |
| `--project <id\|name\|@current>` | 寻址一个工程；命令自己有 project 参数时作默认值 |
| `--dry-run` | 只解析与校验，不写入；返回值说明将发生什么 |
| `--confirm` | 破坏性命令（删除工程/轨）必须带 |
| `--if-revision <n>` | 乐观并发；不匹配 → `CONFLICT`，退出码 4 |
| `--idempotency-key <k>` | 同一个键重放不会二次生效（重试安全） |
| `--envelope` | 打印完整信封（ok / revision / warnings / error），而不是只打印 data |
| `--compact` | 单行 JSON |
| `-q`, `--quiet` | 不输出 stdout（warnings 和 errors 仍在 stderr） |
| `--port <n>` | 默认 47610，或被 `ACAPELLA_AGENT_PORT` 覆盖 |
| `--url <http://…>` | 换一个 base URL（默认 `http://127.0.0.1:<port>`） |
| `--timeout <seconds>` | 单次请求超时，默认 180 |
| `--wait` | 异步命令（如 `beat analyze`）轮询到任务结束 |

## 参数怎么写

位置参数写在选项之前。值的类型由**字面量**推断，不需要引号或类型标注：

| 写法 | 变成 | 例子 |
| --- | --- | --- |
| `92` `0.75` `-1` | number | `--bpm 92` |
| `on` `off` `true` `false` `yes` `no` | bool | `--mute on` |
| `C4` `Bb5` `17:3` `-3dB` `L20` | string（原样透传，单位由服务端解释） | `--pan L30` |
| `@parts.json` | 读文件并解析成 JSON | `--notes @parts.json` |
| `@-` | 从 stdin 读 JSON | `cat p.json \| acapella notes replace … --notes @-` |
| `@track:"名字"` `@current` | **不是文件**：服务端寻址语法，原样透传 | `--track @track:"Bass"` |
| `[1,2]` `{"a":1}` | 行内 JSON | `--ids '[3,4]'` |

kebab-case 选项自动映射成 camelCase 参数（`--beats-per-bar` → `beatsPerBar`）。

## 时间怎么写

时间参数接受四种写法，服务端统一换算：

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

## 怎么指一条轨

| token | 例子 | 说明 |
| --- | --- | --- |
| `midi:<uuid>` | `midi:6F1C…` | MIDI / 合唱轨 |
| stem 名 | `vocals` `drums` `bass` `other` `leadVocal` | 分轨工程里的固定轨 |
| `@track:"名字"` | `@track:"Lead Vocal 1"` | 按 **MIDI 轨名** 找；重名报 `BAD_REQUEST`。音频 stem 用上面的固定 token |

**唯一可靠的 token 来源是 `acapella track list` / `acapella state`** —— 不要凭印象拼。

## 音频怎么进工程（三步，不能跳）

```
acapella upload ~/Desktop/lead.wav          # → fileId（本地文件读成字节推进 App）
acapella take import --file <fileId> --track <录音轨> --at 1:1
acapella track get <录音轨>                  # 读回：文件、时长、起点
```

为什么不能直接给路径：App 在沙盒里，读不到命令行给的任意路径。
`upload` 只把字节搬进容器（**不进时间线**），`take import` 才写工程。
落盘是**整曲对齐**的（第 0 帧 = 歌曲 0 秒），`--at` 之前补静音 —— 这是播放与导出不错位的前提。
`durationSeconds` = 源音频长度；`fileDurationSeconds` = 落盘后的整曲长度，两个数不要混。

## 一条轨的音频怎么改（取出 → 改 → 放回）

```
acapella track audio export vocals --out ./vocals.m4a      # 取出来（唯一出口）
ffmpeg -i ./vocals.m4a -af 'volume=-3dB' ./vocals-fixed.m4a # 随便怎么处理
FID=$(acapella upload ./vocals-fixed.m4a | jq -r .fileId)
acapella track audio replace vocals --file "$FID" --confirm
acapella track audio restore vocals                         # 反悔了，回原版
```

为什么必须走这条：CLI 读不到 App 的沙盒容器，`export` 的产物由 App 复制到中转区、
再经 `GET /download/<id>` 发给你；想直接 `ffmpeg` 处理容器里那个文件是不可能的。
`replace` 落盘是 44.1 kHz 立体声、第 0 帧 = 歌曲 0 秒（与分离产物同口径），
分轨的原文件不会被覆盖，所以 `restore` 只是把记录指回去。
录音 take 换掉就是换掉了（与界面重录同一语义），没有 restore。

## 写一首多人阿卡贝拉（是编曲，不是生成）

```
acapella choir voices                               # 音域表 + 约束（只读，不动工程）
acapella track add --kind midi --name Bass          # 一人一轨：四声部 = 四次
acapella notes replace midi:… --notes @bass.json    # 每个声部写一次，自动重渲染该轨
acapella qc notes && acapella qc mix                # 音域 / 平衡
```

`harmony create` 和 `choir create` 都是**生成**：前者把主唱音频移调渲染成真声，
后者按和弦铺一条模板线 —— 两条路都不需要你写一个音符。
用户说「阿卡贝拉合唱团 / 无伴奏合唱 / 每人一个声部」时要的正好相反：
四条 MIDI 轨、一名歌手一条，音符由你按声部写出来。

`choir voices` 给 SATB 的可写音域（Bass E2–E4 / Tenor C3–A4 / Alto F3–F5 / Soprano C4–C6）、
舒适区、相邻声部最大间距，以及平行五八度与力度分层的约束。
连着 `choir create` 发四次不会变成四声部：它每次只按和弦算一条线、不读别的声部。

## 输出与退出码

```
stdout = data（JSON）      stderr = warnings + errors
exit 0 成功 · 1 CLI/IO 失败 · 2 用法或 BAD_REQUEST · 3 连不上 App
     4 CONFLICT · 5 FORBIDDEN · 6 NOT_FOUND · 7 PRECONDITION_FAILED
     8 UNSUPPORTED · 9 BUSY · 10 LIMIT_REACHED
```

`warnings` 一定看：夹取、改名、被忽略的参数都在里面。**成功后立刻用返回值里的快照说话，不要再猜状态。**
