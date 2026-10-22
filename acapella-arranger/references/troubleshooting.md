# 出错怎么办

先看**退出码**，再看 `error.code`，最后看 `hint`。`hint` 是服务端特意写的下一步动作，
比任何猜测都准。

## 一眼决策

```
acapella doctor
 ├─ ✗ token      → App 设置页打开「AI 控制」（会写 token）；不要手造 token
 ├─ ✗ port       → 端口被占：--port 换一个，或关掉占用者
 ├─ ✗ health     → App 没在跑，或开关是关的
 ├─ ✗ protocol   → CLI 与 App 版本不匹配：brew upgrade acapella
 └─ ✓ 全绿      → 问题在命令本身，看下面
```

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
| `midi import` | 没有该命令 | 把音符贴成 JSON，`notes replace` |
| `harmony …` | 没有该命令 | `track add --kind midi` + `notes replace`（配方 2） |
| `fx …` | 没有该命令 | 只用 `track mix` 的音量/声像 |
| 空工程里 `beat set` 改速 | 空工程的速度在创建时固定 | 新建时给对 `--bpm` |

## App 端异常（`INTERNAL`）

先看 App 是否卡在某个长任务：`acapella job get` 列任务。若 `state` 仍能返回，说明服务还活着，
只是那条命令炸了 —— 换 `--dry-run` 试同一命令能区分"解析炸"还是"执行炸"。

**不要**重启 App 来解决：会丢掉未保存的录音。先 `acapella state` 记下 `revision` 与工程名，
再请用户决定。

## 什么时候该停下来问人

- 要删除工程 / 删除有录音的轨。
- 要覆盖已录的 take。
- `doctor` 四项里有红的，且用户在场。
- 同一个命令连续两次失败且 `hint` 没变。
