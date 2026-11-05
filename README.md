# acapella-skill

给 AI 用的 Acapella 操作手册。AI 通过 **本机 MCP 服务**（Model Context Protocol，
Streamable HTTP）驱动 macOS 上的 Acapella.app —— 建工程、写音符、按和弦编配、
生成 MIDI 合唱、混音、练习循环、换某条轨的音频、导出与质检。

**不需要安装任何命令行工具。** 旧版是通过 `acapella` CLI 驱动的，CLI 已经下线，
App 自己就是 MCP 服务端，客户端用你已经在用的那个 AI 就行。

| skill | 说明 |
| --- | --- |
| [`acapella-arranger`](acapella-arranger/SKILL.md) | 全部工具的使用说明与决策规则（65 个工具） |

## 前置

1. macOS + [Acapella.app](https://acapella.online)
2. App 里 **设置 → AI 控制**，打开开关（默认关闭）
3. 记下设置页显示的两样东西：**MCP 端点**（形如 `http://127.0.0.1:47610/mcp`）和 **token**

端点只有本机可达，关闭开关即失效；端口被占时 App 会顺延到 47611–47620，
**以设置页显示的为准**，不要假设 47610。

## 安装 skill

把 `acapella-arranger` 整个目录放进你所用客户端的 skills 目录：

```bash
git clone https://github.com/govo/acapella_skill.git
cp -R acapella_skill/acapella-arranger ~/.workbuddy/skills/     # 路径按你的客户端改
```

开发时用软链，改文件立即生效：

```bash
ln -sfn "$PWD/acapella-arranger" ~/.workbuddy/skills/acapella-arranger
```

装完在客户端的 skill 列表里应该能看到 `acapella-arranger`（软链也认）。

## 接上 MCP 服务

把下面这段写进客户端的 MCP 配置，`url` 与 `Authorization` 换成设置页上的真实值：

```json
{
  "mcpServers": {
    "acapella": {
      "type": "http",
      "url": "http://127.0.0.1:47610/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

少数客户端不认 `type` 字段，删掉即可（`url` + `headers` 是必须的）。

**只有 shell 的时候**用本 skill 自带的薄壳 —— 它自己扫端口、自己带 token：

```bash
mkdir -p ~/.config/acapella
echo '<token>' > ~/.config/acapella/token && chmod 600 ~/.config/acapella/token
acapella-arranger/scripts/mcp.sh health     # 通了再往下
acapella-arranger/scripts/mcp.sh call state # 看当前工程
```

token 也可以走环境变量 `ACAPELLA_MCP_TOKEN`，优先级高于文件。

## 验证

```bash
scripts/mcp.sh health                      # {"listening":true,...}
scripts/mcp.sh call state                  # 当前工程、轨道、revision
scripts/check-tools.sh                     # 文档与 tools/list 是否一致
```

`health` 不通只有两个原因：App 没开，或 AI 控制没开。别改端口、别手造 token。

## 结构

```
acapella-arranger/
├── SKILL.md                    # 每次会话读的正文：接入、铁律、工具地图、工作流
├── references/
│   ├── opening.md              # 用户不知道怎么开口时怎么办（第一次对话前先读）
│   ├── commands.md             # 65 个工具全表（人维护，check-tools.sh 校验）
│   ├── recipes.md              # 可复制的成套配方
│   ├── music.md                # 声部表 / 音域 / 和弦展开 / 混音起点
│   ├── harmony.md              # 和声与 MIDI 合唱的边界
│   └── troubleshooting.md      # 错误码 → 决策树
└── scripts/
    ├── mcp.sh                  # JSON-RPC 薄壳：health / tools / call / upload / download
    ├── check-tools.sh          # 校验 commands.md 与 tools/list 一致
    ├── qc.sh                   # 交付闸门：阈值不过退出非 0
    ├── arrange_from_chords.sh  # 和弦进行 → 四条声部 notes JSON
    └── demo_twinkle.py         # 端到端样例：旋律 → 编曲 → 混音 → 导出 → 质检
```

## 维护

**`commands.md` 不要手写。** 工具表由 App 的 `AgentCommandTable` 派生，
所以文档由人维护、由脚本校验：

```bash
scripts/check-tools.sh          # 报告两个方向：服务端有文档没写 / 文档有服务端没有
scripts/check-tools.sh --table  # 打出最新工具表，人工贴回文档
```

改 `SKILL.md` 时守住两条：

1. 只写**必须记住**的规则与决策，细节推给 `references/`。
2. 每条工具都必须是真存在的 —— 以 `tools/list` 为准，别写"用 `harmony.stack` 编和声"，
   AI 会照着调，然后失败。

## 版本

`metadata.version` 跟 skill 内容走，不跟 App 版本走。当前 **1.1.1**。

- 1.1.1 — 清掉 `music.md` 与两处脚本注释里残留的 CLI 写法（`qc notes` → `qc.notes`、
  `beat set` → `beat.set`、`--volume -2dB` → `track.mix {volume: "-2dB"}` 等）；
  修正 `export --video` 这个**并不存在**的工具（实际只有 `export.mix` / `export.tracks`）；
  `troubleshooting.md` 的换端口说明补上可靠做法（直接跑包内二进制，`open --args` 不可靠）
- 1.1.0 — 新增 `references/opening.md`：用户不知道怎么开口时的开场三问、默认值与话术对照
- 1.0.0 — 从 CLI 切到本机 MCP（65 个工具）；`gen-commands.sh` → `check-tools.sh`
