# 出错怎么办

先看**退出码**，再看 `error.code`，最后看 `hint`。`hint` 是服务端特意写的下一步动作，
比任何猜测都准。

## 一眼决策

```
acapella doctor
 ├─ ✗ token      → App 设置页打开「AI 控制」（会写 token）；不要手造 token
 ├─ ✗ port       → 端口被占：CLI 已自动扫 47610–47620；仍连不上才换 --port，
 │                 或关掉占用者
 ├─ ✗ listening ✗ no answer (port held)
 │               → 端口上有个**僵死进程**：TCP 握得上、HTTP 不回，kill -9 也清不掉
 │                 活动监视器强退那个残留 Acapella，或重启电脑
 ├─ ✗ health     → App 没在跑，或开关是关的
 ├─ ✗ protocol   → CLI 与 App 版本不匹配：brew upgrade acapella
 └─ ✓ 全绿      → 问题在命令本身，看下面
```

> 「连不上」有两种，处置完全不同，别混：
> **拒绝连接** = App 没开 / 端口不对；**连上但无响应** = 端口被僵死进程占着。
> 后者换 `--port` 只在**新起一个实例**时有用；`open -a Acapella --args --agent-port 47612`
> 在部分 macOS 版本上根本不会把参数传进 App，别指望它。
>
> 端口发现：App 默认绑 47610，被占时自动顺延 47611–47620；CLI 连不上默认端口时
> 自动扫这一段找 `/health`（`doctor` 会标注 auto-discovered）。显式 `--port` 时
> 不扫描 —— 用户说了算。

## 退出码 → 下一步

| 码 | 含义 | 先做什么 | 常见真因 |
| --- | --- | --- | --- |
| 0 | 成功 | 看 `warnings` | — |
| 1 | CLI/IO 或 `INTERNAL` | 重试一次；仍失败看 stderr 的 JSON | 写文件失败、App 内部异常 |
| 2 | 用法错 / `BAD_REQUEST` | 读 `hint`，`acapella <cmd> --help` | 参数名拼错、时间格式错、重名寻址歧义 |
| 3 | 连不上 | `acapella doctor` | App 未启动 / 开关关 / token 错 / 端口不符 |
| 4 | `CONFLICT` | `acapella state` 取新 revision | `--if-revision` 过期；别人先改了 |
| 5 | `FORBIDDEN` | 看当前档位 | 只读档发写命令；`own` 档才能删 |
| 6 | `NOT_FOUND` | `track list` / `project list` 重取 token | token 用了旧名字或旧 id |
| 7 | `PRECONDITION_FAILED` | 补前置条件 | 没节拍网格、循环未设 A/B、工程未打开 |
| 8 | `UNSUPPORTED` | 换条路或告诉用户此版本没有 | `project import`、`midi import`、空工程改速 |
| 9 | `BUSY` | 等当前操作结束再试 | 正在录音 / 正在导出 / 正在分析 |
| 10 | `LIMIT_REACHED` | 减少批量 | 一次写的音符数或轨数超上限 |

## `BAD_REQUEST` 的四个高频

1. **`unknown track token`** → token 不对。合法形式只有三种：
   `midi:<uuid>`、stem 名（`vocals` `drums` `bass` `other`…）、`@track:"MIDI 轨名"`。
   注意 `@track:` 只按 **MIDI 轨**名字查找；音频 stem 必须用固定 token。
2. **`cannot parse time`** → 时间写法错。合法：`12.5` / `1:04` / `17:3` / `tick:960` / `start` / `end`。
   `17:3` 是小节:拍，不是分:秒 —— 想写 17 分 3 秒要用 `17:03`。
3. **`ambiguous track name`** → 有重名轨。改用 `midi:<uuid>`，或先 `track rename` 区分。
4. **`notes must be an array`** → `@file` 没读到或文件不是数组。`cat parts.json | head -c 80` 检查。

## `NOT_FOUND`

```
NOT_FOUND → acapella track list        （轨）
          → acapella project list      （工程）
          → acapella state             （当前工程是不是你想要的那个）
```

**不要**用"名字应该没变"来推理。夹取警告、重名改名都会让旧 token 失效。

## `PRECONDITION_FAILED`

| `hint` 里出现 | 缺什么 | 补法 |
| --- | --- | --- |
| `beat` / `grid` | 没有节拍网格 | `beat set --bpm 92` 或 `beat analyze --wait` |
| `loop` / `A` `B` | 循环没设端点 | `loop set 17:1 25:1` 再 `loop enable` |
| `no project` / `open` | 没有打开工程 | `project open <id>` 或 `project create …` |
| `recording` | 正在录音 | 等录音结束（`state.transport` 里看） |

## `CONFLICT`

乐观并发保护 —— 不是错误，是"你手上的事实过期了"。

```bash
acapella state | jq .revision        # 拿新 revision 重新决定，再重发
```

不要靠"再试一次"绕过：那会让基于旧状态的修改覆盖别人的改动。

## `UNSUPPORTED`（这个版本的真实边界）

| 命令 | 为什么不行 | 替代 |
| --- | --- | --- |
| `project import` | 导入成品工程要跑分离、建记录、算节拍，入口必须是用户选文件 | 让用户在 App 里导入；自己的音频走 `upload` + `take import` |
| `midi import` / `midi export` | 没有该命令 | 把音符贴成 JSON，`notes replace` |
| `fx …` | 没有该命令 | 只用 `track mix` 的音量/声像 |
| 空工程里 `beat set` 改速 | 空工程的速度在创建时固定 | 新建时给对 `--bpm` |
| 空工程里 `beat analyze` | 没有可分析的音频（即使已经 `take import`） | 同上：建工程时给对 BPM |
| `key analyze` | 没有该命令（合唱取调不需要它） | `key get` / `key set` |
| `track audio replace` 打到**真声合唱轨** | 它的音频是从源轨渲染出来的，不是可替换的文件 | 换源轨，再 `harmony create` |
| `track audio replace` 打到**纯 MIDI 轨** | 它的声音由音符渲染，没有音频文件 | `notes replace` → `track render` |
| `track audio restore` 打到**录音 take** | take 换掉等于重录一遍，没有"原文件" | 没有撤销；换回来只能再 `replace` 一次旧素材 |

## 轨道音频（`track audio *`）专有的四个错

| 现象 | 真因 | 处理 |
| --- | --- | --- |
| `error: unknown command \`track audio\`` | 手上的 `acapella` 二进制早于这条命令 | `brew upgrade acapella`，或换用最新构建 |
| `GET /download/…` 回 404 | 中转区文件只留 6 小时，`downloadId` 过期 | 重新 `track audio export` 拿新 id |
| `BAD_REQUEST: would cover Xs but the project is Ys` | 加了 `--fit reject`，素材长度与工程差超 0.25 s | 去掉 `--fit reject`（会补静音），或先把素材裁/补到整曲长 |
| `PRECONDITION_FAILED: has not been replaced by the agent` | 想 `restore` 但当前文件本来就是原分离文件 | 没什么可撤的；先 `replace` 再谈 `restore` |
| `PRECONDITION_FAILED: the original … is gone` | 原分离文件被删/工程被重新分离过 | 重新分离，或直接用 `replace` 放回你要的音频 |

容差内的长度差**不会**报错，但会有 `warning: … ends at X s — Y s of the project tail will be silence`。
这不是噪音：不处理的话导出末尾就是一截静音。

## 阿卡贝拉合唱（`choir voices`）——三个**不报错**的错

| 现象 | 真因 | 处理 |
| --- | --- | --- |
| 用户要「四人阿卡贝拉」，你交了 `harmony create` 的结果 | 那是对主唱移调渲染，产出「同一个人唱的另一个音高」，四个独立声部根本没出现 | 那份结果当和声留着可以，但阿卡贝拉本体得 `track add --kind midi` × N + 自己写音符（工作流 F） |
| 建到第三条 MIDI 轨回 `LIMIT_REACHED` | 免费档每工程 MIDI 轨数有限（四声部要 4 条） | 先看 `caps` 的额度再规划；装不下就如实告诉用户（升级或退二声部），**不要**偷偷删掉用户别的轨 |
| 四条轨都有音符，听着却像合成器铺底 | 声部跨界、间距开洞、连续平行五度/八度、四条力度一模一样 | 拿 `choir voices` 的 `voices` + `rules` 逐条对：音域、八度间距、平行进行、velocity 分层 |
| `track instrument … ooh` 回 `LIMIT_REACHED`（`feature: vocal_vowel_pro`） | 免费档的人声只用能用「啊」，其余 7 个元音是 Pro | 换成 `--instrument ah`（或任意非人声音色）；想知道还能选什么用 `acapella instrument list` / `caps.features.instruments` |
| 某条轨 `instrumentLocked: true`，你担心"不合规" | 那是**已经选过**的 Pro 元音（付费期选的 / 别人分享的工程），照常出声照常可编辑 | **什么都别做**。它只是不能再被重新选中；改回「啊」等于把用户的编曲改坏 |

`choir create` 连发四次**不会**变成四声部：它每次只按和弦算一条线、不读别的声部，
四条线不会互相避让（撞音、平行五度、间距开洞都会出现）。

## App 端异常（`INTERNAL`）

先看 App 是否卡在某个长任务：`acapella job get` 列任务。若 `state` 仍能返回，说明服务还活着，
只是那条命令炸了 —— 换 `--dry-run` 试同一命令能区分"解析炸"还是"执行炸"。

**不要**重启 App 来解决：会丢掉未保存的录音。先 `acapella state` 记下 `revision` 与工程名，
再请用户决定。

## 什么时候该停下来问人

- 要删除工程 / 删除有录音的轨。
- 要覆盖已录的 take。
- 要 `track audio replace` 某条轨的音频：分轨还能 `restore`，**take 换掉就回不去**。
- `doctor` 四项里有红的，且用户在场。
- 同一个命令连续两次失败且 `hint` 没变。
