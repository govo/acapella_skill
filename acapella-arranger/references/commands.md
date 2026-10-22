# `acapella` CLI — 命令全表

由 `acapella docs` 从 CLI 自己的命令表生成（v0.1.0，协议 1）。**不要手改**：改 CLI 的命令注册表，再跑 `scripts/gen-commands.sh`。

共 60 条命令。

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
| `project create <name> [--bpm 92] [--beats-per-bar 4] [--bars 64]` | 新建空工程并打开（返回完整快照） |
| `project open [<id\|name>]` | 打开一个工程（会切走界面）并返回快照 |
| `project close` | 关闭当前工程，回到列表 |
| `project rename <id\|name> <new-name>` | 改工程名 |
| `project star [<id\|name>] [--star off]` | 收藏 / 取消收藏 |
| `project delete <id\|name> --confirm` | 删除工程（破坏性：需要 own 档 + --confirm） |
| `project import <file>` | 导入音频/视频成新工程（未实现：需要用户在 App 里选文件） |

**`project create`**
> 空工程只有人声轨可以加（分轨模型不存在）。长度给 --bars 或 --duration 二选一，
> 夹取会出现在 warnings 里 —— 不要忽略。

**`project import`**
> 和 `upload` 不是一回事：上传解决的是"把一段音频放进**已打开**的工程"（`take import`），
> 导入工程要跑分离、建记录、算节拍，入口必须是用户亲手选的那个文件。
> 硬塞上传的字节等于绕过分离流程造一个半成品工程，所以这里明确报 UNSUPPORTED。

## 轨道

| 命令 | 作用 |
| --- | --- |
| `track list` | 轨道列表（时间线顺序、类型、混音状态、音符数、有没有音频） |
| `track get <track>` | 这条轨里到底是什么：音频文件、时长、采样率、take 元数据 |
| `track add [<name>] [--kind midi\|vocal] [--after <track>]` | 加一条轨：vocal（仅空工程）或空 MIDI 轨 |
| `track rename <track> <new-name>` | 改轨名 |
| `track delete <track> --confirm` | 删除轨道（破坏性：需要 --confirm） |
| `track move <track> [--to 3] [--after <track>]` | 移动轨道到某个位置或某条轨之后 |
| `track mix <track> [--volume -3dB] [--pan L20] [--mute on] [--solo on]` | 调一条轨的音量 / 声像 / 静音 / 独奏 |
| `track fold <track> [on\|off]` | 折叠 / 展开轨道（只影响显示） |
| `track render <track>` | 把 MIDI 轨渲染成音频（写完音符统一渲染一次） |

**`track get`**
> 读的是播放引擎真正调度的那个文件。分轨给源文件；MIDI / 合唱 / take 给整曲对齐的
> 渲染 WAV。音频类字段在 `audio` 里，take 轨另外带 `take`（起点、时长、归属）。

**`track mix`**
> 音量写 0.7 或 -3dB 都行；声像写 L30 / R15 / -0.3 / 0。
> 注意 solo 会让其他轨在导出里变静音 —— 返回值里会带 warning。

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

## 音频

| 命令 | 作用 |
| --- | --- |
| `upload <file>` | 把本地音频文件推进 App 容器，返回 fileId（给 take import 用） |
| `take import --file <fileId> --track <track> [--at 1:1] [--name "主唱 1"]` | 把上传的音频写成整曲对齐 WAV，挂到某条录音轨上 |
| `take list [--track <host>]` | 工程里所有 take：挂在哪条轨、从第几秒开始、多长、有没有声 |
| `take get <track>` | 读一条 take（给 take 的 token），或一条宿主轨下面的全部 take |

**`upload`**
> 传的是**文件本身的字节**，不是路径。App 收下后会立刻解码校验：解不开的文件当场报
> BAD_REQUEST（而不是等到 take import 才失败）。返回值里的 `fileId` 是下一步的入参。
> 上传只把字节搬进容器，**不进时间线**——真正落进工程要接着跑 take import。
> 上传区保留 24 小时，过期后 fileId 失效，重新上传即可。

**`take import`**
> `--track` 给宿主轨：空项目的人声轨（写进它自己）、分轨主唱（新建 Take 子轨）、
> 或任意 MIDI 轨（新建 Take 子轨）。给一条**已有 take** 的 token 表示覆盖那条的内容，
> 这时必须加 --confirm。
> 落盘口径与录音完全一致：44.1k 立体声、第 0 帧 = 歌曲 0 秒，`--at` 之前的空白由
> 静音补齐。返回的 `durationSeconds` 是**源音频**长度，`fileDurationSeconds` 是落盘
> 后的整曲长度——两个数不要混。
> 例：`acapella upload ~/Desktop/lead.wav` → `acapella take import --file <id> --track midi:… --at 9:1`

**`take list`**
> 给 `--track` 就只看那条宿主轨下面的。`audio` 里是峰值 / RMS / 是否削波。

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

## 输出与退出码

```
stdout = data（JSON）      stderr = warnings + errors
exit 0 成功 · 1 CLI/IO 失败 · 2 用法或 BAD_REQUEST · 3 连不上 App
     4 CONFLICT · 5 FORBIDDEN · 6 NOT_FOUND · 7 PRECONDITION_FAILED
     8 UNSUPPORTED · 9 BUSY · 10 LIMIT_REACHED
```

`warnings` 一定看：夹取、改名、被忽略的参数都在里面。**成功后立刻用返回值里的快照说话，不要再猜状态。**
