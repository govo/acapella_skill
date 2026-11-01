# acapella-skill

给 AI 用的 Acapella 操作手册。目前只有一个 skill：

| skill | 说明 |
| --- | --- |
| [`acapella-arranger`](acapella-arranger/SKILL.md) | 用 `acapella` CLI 驱动 Acapella.app：建工程、写音符、编四声部、混音、练习循环、改某条轨的音频、导出与质检 |

配套两处：

- CLI 二进制：[`govo/acapella-cli`](https://github.com/govo/acapella-cli) — `brew install govo/tap/acapella`
- Homebrew tap：[`govo/homebrew-tap`](https://github.com/govo/homebrew-tap)

## 安装

### 软链（开发时用，改文件立即生效）

```bash
ln -sfn "$PWD/acapella-arranger" ~/.workbuddy/skills/acapella-arranger
```

### 复制

```bash
cp -R acapella-arranger ~/.workbuddy/skills/
```

装完在 skill 设置页应该能看到 `acapella-arranger`（软链也认）。

## 结构

```
acapella-arranger/
├── SKILL.md                  # 每次会话都读的正文（≤200 行）
├── references/
│   ├── commands.md           # 69 条命令全表 —— 由 `acapella docs` 生成，别手改
│   ├── music.md              # 声部表 / 音域 / 和弦展开 / 混音起点
│   ├── recipes.md            # 8 个可复制的配方
│   └── troubleshooting.md    # 错误码 → 决策树
└── scripts/
    ├── qc.sh                 # 交付闸门：阈值不过退出非 0
    ├── arrange_from_chords.sh# 和弦进行 → 四条声部 notes JSON
    ├── demo_twinkle.py       # 端到端样例：旋律 → 编曲 → 混音 → 导出 → 质检
    └── gen-commands.sh       # 重新生成 references/commands.md
```

`commands.md` 是 62 条**服务端**命令 + 7 条**本地**命令。要判断某条命令在不在，
以 `acapella caps` 为准（本地命令不在里面）。

## 维护

**命令表不要手写。** CLI 的命令一改，重跑：

```bash
cd acapella-arranger
./scripts/gen-commands.sh
# 开发机没装 acapella 时：
ACAPELLA_BIN=../Acapella/Acapella/CLI/.build/debug/acapella ./scripts/gen-commands.sh
```

`commands.md` 的数据源是 CLI 自己的命令注册表（`acapella docs`），所以不存在"文档落后于代码"。

改 `SKILL.md` 时守住两条：

1. 只写**必须记住**的规则与决策，细节推给 `references/`。
2. 每条命令都必须是真存在的 —— 这个版本没有 `harmony` / `fx` / `midi import` 命令，
   别在文档里写"用 `acapella harmony stack` 编和声"，AI 会照着调用然后失败。

## 版本

`SKILL.md` 的 `metadata.version` 跟着 CLI 的发布版本走（`requires` 写同一条底线）。
当前：CLI 0.4.0 / 协议 1。

`track audio export/replace/restore` 是 0.4.0 才有的能力，`requires` 卡在 0.4.0 就是为了
让老 CLI 上的 AI 不要以为自己能取音频 —— 它会在 `unknown command` 上白绕一圈。

