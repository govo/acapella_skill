# 合唱：真声合唱 / MIDI 合唱 / 手写阿卡贝拉

> 这一页对应 App 里**轨头右键菜单**的三节合唱。CLI 走的是同一个入口，
> 所以这里写的每一条顺序约束，在界面和命令行上都成立。

---

## 0. 三条路，先分清

| 用户要的 | 命令 | 谁写音符 | 产物 |
| --- | --- | --- | --- |
| 给主唱加一层和声 | `harmony create` | 机器 | 渲染好的音频（`role = vocalHarmony`） |
| 按和弦铺一条陪衬线 | `choir create` | 机器套模板 | MIDI 轨（`role = choir`） |
| **阿卡贝拉合唱团：多人、无伴奏、一人一声部** | `choir voices` → `track add` × N → `notes replace` × N | **你** | N 条普通 MIDI 轨（`role = midi`） |

前两条是**生成**：选一个类型 / 声部串，App 自己算音、自己渲染，AI 不参与作曲。
第三条是**编曲**：没有任何生成入口，音符是 AI 按声部一个个写的。

判断口径：用户说「丰富主唱」「加点和声」→ 第一条；说「铺个低音线」「来个琶音」→ 第二条；
说「阿卡贝拉」「无伴奏合唱」「四个人四个声部」「合唱团」→ 第三条。

### 0.1 第三条的音色怎么选

`choir create` 铺出来的轨用的是非人声音色（低音 `synth.bass` / 琶音 `synth.electricPiano` /
长音 `synth.sine`）—— 它们**免费档全开**，不用管档位。

手写阿卡贝拉（第三条）才会用到人声元音：8 个元音 × 男女 = 16 个 id。

| 档位 | 能选 |
| --- | --- |
| 免费 | 只有**「啊」**：`synth.choirAh`（女）/ `synth.choirAhMale`（男） |
| Pro | 全部 16 个（呜 / 噢 / 嗯 / 啊呀 / 咦 / 哦呜 / 嘿 + 啊） |

```bash
acapella track instrument <Soprano> ah --voice female
acapella track instrument <Tenor>   ah --voice male
```

- 给免费用户编声部就用 `ah`，别写 `ooh` / `ee` —— 会 `LIMIT_REACHED`（`vocal_vowel_pro`）。
- 想复刻「嘟 · 哇 · 哼」的多音节织体：免费档做不到，先看 `caps.features.instruments` 再决定
  （要么降级成纯「啊」的织体，要么如实告诉用户这是 Pro 能力）。
- 轨道上**已经存着**的 Pro 元音（`instrumentLocked: true`）照常出声、照样能写音符，
  **不要**为了"合规"改回「啊」。详见 `SKILL.md` 的「音色与免费边界」。

---

## 1. 三节菜单与命令的对应关系

| 右键菜单节 | 标题 | CLI | 数量 |
| --- | --- | --- | --- |
| 1 | Vocal Harmony (audio) | `harmony options` / `harmony create` | 21 类 |
| 2 | MIDI Choir | `choir options` / `choir create`（`bass.*` `arpeggio.*` `rootThirdArp.*`） | 12 串 |
| 3 | Parallel long notes | `choir create`（`parallel.*`） | 24 串 |

菜单只对「能当人声源」的轨出现：主唱分轨（`vocals`）或录音轨（`role = recording`）。
源轨**还没音频**时，三节整块置灰但不消失 —— CLI 对应的是 `PRECONDITION_FAILED`，不是 `NOT_FOUND`。

## 2. 真声合唱的 21 种类型

`harmony create --type` 收三种写法：数字（`2`）、英文名（`thirdAbove`）、中文显示名（`上三度`）。

| # | type | 声部数 | 中文 |
| --- | --- | --- | --- |
| 1 | thirdBelow | 1 | 下三度 |
| 2 | thirdAbove | 1 | 上三度 |
| 3 | thirdBelowAndAbove | 2 | 下三度 + 上三度 |
| 4 | fourthBelow | 1 | 下四度 |
| 5 | fourthAbove | 1 | 上四度 |
| 6 | fourthBelowAndAbove | 2 | 下四度 + 上四度 |
| 7 | fifthBelow | 1 | 下五度 |
| 8 | fifthAbove | 1 | 上五度 |
| 9 | fifthBelowAndAbove | 2 | 下五度 + 上五度 |
| 10 | thirdBelowFifthAbove | 2 | 下三度 + 上五度 |
| 11 | fifthBelowThirdAbove | 2 | 下五度 + 上三度 |
| 12 | octaveBelow | 1 | 低八度 |
| 13 | octaveAbove | 1 | 高八度 |
| 14 | octaveBelowAndAbove | 2 | 低八度 + 高八度 |
| 15 | vocalStack3 | 3 | 人声叠置（3 声部） |
| 16 | vocalStack4 | 4 | 人声叠置（4 声部） |
| 17 | powerChord | 2 | 强力和弦 |
| 18 | parallelSecond | 1 | 平行二度 |
| 19 | drone | 1 | 持续音 |
| 20 | unison2 | 2 | 同度齐唱（2 声部） |
| 21 | unisonOctaves4 | 4 | 同度 + 八度（4 声部） |

**多声部类型落成多条轨**（每声部一条），不是一条轨里塞两个声部。
理由：一条轨混两个声部时，音量 / 声像 / 重新生成 / 跟唱录音只能整组一起动。

`--level` 是和声总线电平（相对主唱的比例，`(0, 1]`，默认 0.6）——**不是 dB**。

## 3. MIDI 合唱的 36 个声部串

```
bass.quarter | bass.half | bass.dottedHalf | bass.whole
arpeggio.{below,above,unison}.{quarter,eighth}
rootThirdArp.{quarter,eighth}
parallel.{above,below}.{third,fourth,fifth,octave}.{quarter,half,dottedHalf,whole}
```

`acapella choir options` 给全表，含 `displayName` 与 `trackName`（生成的轨会叫这个名字）。

## 4. 顺序：谁必须等谁

```
project create  →  take import  →  key set  →  harmony/choir create
     │                  │              │                │
   等工程加载完      等 hasAudio     等 duration>0    等队列跑空
```

| 步骤 | 等什么 | 抢跑的表现 |
| --- | --- | --- |
| `project create` | 记录落盘 + 加载完成 | **静默什么都不做**（守卫直接 return，不报错） |
| `take import` | 目标轨能接 take | `PRECONDITION_FAILED` |
| `key set` | 工程有时长 | `PRECONDITION_FAILED: no duration yet` |
| `harmony/choir create` | 源轨有音频 | `PRECONDITION_FAILED: … has no audio yet` |
| `create` 返回 | 队列空 + 不在消费 + 没有在生成 | 拿到没有波形的空壳轨 |

`create` **自己会等**（判据是 `harmonyGenerationQueue.isEmpty && !isDrainingHarmonyGeneration && !isGeneratingHarmony`），
返回值里有 `waitedSeconds` 可直接核对。实测：真声合唱 8–9 秒/条，MIDI 合唱 21–24 秒/条。

**不要并发连发。** 它们共用一条串行队列，并发只是排队，不会更快；
而且 `isGeneratingHarmony` 是单锁，抢跑的那条会被直接挡掉。

## 5. 调性：合唱取音的五级链

这是最容易搞错的一环。`key set --key C` 写的是**调性轨首段**（第 1 顺位）；
和弦面板那个「指定调号」下拉才是第 4 顺位 —— 两者不是一份数据。

| 顺位 | 条件 | 取什么 |
| --- | --- | --- |
| 1 | 该段 `keyName` 非空 | 用它（**不看 `isInferred`**） |
| 2 | 该段为空 | 沿用前一段 |
| 3 | 前面全空 | 该段 f0 现场推断 |
| 4 | 推不出 | `detectedKey`（= 界面「指定调号」下拉，**不是** `key set`） |
| 5 | 还没有 | 全曲 f0 推断 |

所以：

- **不管是整曲还是转调，都写调性轨**：`key set --key C`（整曲）、`key set --key G --at 17:1`（转调点）。
- 「指定调号」下拉（`detectedKey`）只当兜底；CLI 没有单独写它的必要。
- **复核** → `key get`，看 `hasKeyTrack`、`effective`（声明口径）与 `spans`（逐段）。
  `hasKeyTrack = false` = 调性轨上还没有人手动定过调，此时 `effective` 来自推断或 detected。

转调歌必须用 `--at`：一次定一个整曲调，中段一定跑偏。

## 6. 生成完怎么验收

```bash
acapella harmony create --source midi:… --type thirdAbove --level 0.6
# → created[] 里每条都要 hasAudio = true
acapella track get midi:…        # 具体文件、时长、采样率
acapella take list               # peak / RMS / hasSignal，确认"真的有声"
```

真声合唱轨 `noteCount = 0` 是**正常**的：它装的是渲染好的音频，不参与钢琴卷帘编辑。
MIDI 合唱轨反过来，`noteCount > 0` 才算编出来了。

## 7. 常见失败

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `cannot be a harmony source` | 源轨是鼓/贝斯等分轨，或不是录音宿主轨 | 选 `vocals` 或 `role = recording` 的轨 |
| `has no audio yet` | 还没 `take import` / 还没录音 | 先放音频 |
| `create` 返回空 `created[]` | 队列跑空但没新增轨（多因源音频读不出） | `track get` 看源轨文件；看 `warnings` |
| 和声听着跑调 | 没定调，或调性轨里有错的段 | `key get` 看 `spans`；必要时 `key set --key … --at …` |
| 只有一条轨更新（多声部类型） | 并发发了两次 | 串行发，等上一条返回 |

## 8. 手写阿卡贝拉（SATB，一人一轨）

`acapella choir voices` 返回的就是这一节的数据（JSON），直接读，不要背。

| 声部 | 可写音域 | 舒适区 | 角色 |
| --- | --- | --- | --- |
| Soprano 女高音 | C4–C6（60–84） | E4–A5 | 最高声部，通常带旋律 |
| Alto 女低音 | F3–F5（53–77） | A3–D5 | 内声部，填三度 / 七度 |
| Tenor 男高音 | C3–A4（48–69） | E3–G4 | 内声部偏低，常与 Alto 交叉 |
| Bass 男低音 | E2–E4（40–64） | G2–C4 | 和声地基，根音 / 五度 |

建法与八条硬约束见 SKILL.md **工作流 F**。这里只补三条容易忽略的：

1. **为什么不能用 `harmony create` 顶替**：它是对主唱音频逐帧移调，产出的是
   「同一个人唱的另一个音高」。阿卡贝拉要的是**四个声部同时存在、互相咬合**，
   这件事只能由音符决定，不能由移调决定。
2. **为什么不能用 `choir create` 连发四次**：它每次只按和弦算一条线，**不读其它声部**。
   四条各自算出来的线不会互相避让 —— 撞音、平行五度、间距开洞都会出现，
   听感是四条陪衬线，不是一首合唱。
3. **额度先看清**：生成路线只占真声合唱额度，手写四声部要 4 条 MIDI 轨。
   先看 `caps`，装不下就如实告诉用户（升级或退成二声部），别在第三条轨上撞 `LIMIT_REACHED`。
