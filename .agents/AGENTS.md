# YMind — Agent 说明

macOS 思维导图应用：**Swift + SwiftUI（壳）+ Metal（画布）**，单窗口 + 中心辐射布局。HTML 原型在 `prototype/`。

Agent 配置统一在 **`.agents/`**（skills、MCP、rules），不绑定 IDE。

## 文档语言（强制）

**本仓库所有文档一律中文优先**（`AGENTS.md`、`.agents/`、`docs/`、PR、变更记录）。专有名词 / API / 代码标识符可保留英文。

## MCP

从 `.agents/mcp.json` 注册，启动时以**仓库根为 cwd**：

1. **`XcodeBuildMCP`** — `xcodebuildmcp mcp`。构建 / 运行 / 测试 / 日志 / UI 优先走它。
2. **`xcode`** — `xcrun mcpbridge`。Xcode IDE 桥接（预览 / IDE 状态），需已打开 Xcode 26.3+。

名为 `xcodebuildmcp`、`xcodebuildmcp-cli`、`axiom-xcode-mcp` 的 skill 是使用说明，不是服务器本身。

## Skills

**YMind 专属技能（本仓库自建，不在 lockfile 管理）—— 改核心代码前优先读：**

| Skill | 何时使用 |
|-------|----------|
| `ymind-pm` | 需求探索 / 痛点分析 / 外部调研（Google·X·竞品）/ 找下一个 idea / 写 PRD 之前的思考。产出需求文档 + HTML 原型图，正式 PRD 交 bmad-prd |
| `ymind-command` | 新增/修改改变树结构的命令（CommandBus + Undo） |
| `ymind-codec-version` | 改 `.ymind` schema、节点字段、序列化/版本升迁 |
| `ymind-layout-snapshot` | 扩展布局算法 / NodeFrame / EdgeGeometry / Render-Layout 接缝 |
| `ymind-render-text` | 文字纹理、TextAtlas、坐标系/Retina/缓存 |

**第三方 skill**（`npx skills` 安装，各自 `SKILL.md` 的 `description` 自动路由）：
- 完整路由表见 **[`.agents/rules/ymind-apple-stack.md`](rules/ymind-apple-stack.md)**（实现 Apple 平台代码前先查）。
- 画布优先序：`metal-gpu` → `metal-shader-expert` → `axiom-graphics`（`resizable-rendering.md` / `display-performance.md`）。

## 基础约束

- 优先用 **codegraph mcp** 检索代码；具体约束与 path 见 **[`.agents/rules/ymind-code-retrieval.md`](rules/ymind-code-retrieval.md)**。
- 需要分析**图片内容**且父会话看不了 / 图多需精读时，委派视觉子代理（模型 `ark/glm-5.3-flash`）；触发条件、启动方式与提示模板见 **[`.agents/rules/ymind-vision-delegate.md`](rules/ymind-vision-delegate.md)**。
- 图形（流程图 / 类图 / 架构图）优先用 **Mermaid**。

## Claude 常犯的错误（犯两次就写进这里）

- **改树绕过命令栈** → Undo 失真。改树必走 `commandBus.execute(...)`；相机/选中/搜索态不入栈。见 `ymind-command`。
- **改 `.ymind` schema 不递增 `currentVersion`、不写迁移** → 老文件打不开。见 `ymind-codec-version`。
- **深层节点带 `side`** → side 只存根下一层，`sanitize` 会强制清掉。见 `ymind-codec-version`。
- **改文字渲染删掉行翻转** → 文字颠倒/错位。保留 `TextTextureRasterizer.flipVertically`。见 `ymind-render-text`。
- **Render 层去读 Model** → Metal 只消费 `LayoutSnapshot`，不懂树。见 `ymind-layout-snapshot`。
- **新增依赖没进 `scripts/check-boundaries.sh` 白名单** → 构建即红。新依赖同步更新白名单与 `docs/架构现状.md` §5。

## 更新 Skills

```bash
npx skills update -p -y
# 或从 lockfile 恢复：
npx skills experimental_install
```

## 第一版明确不做

多文档（`DocumentGroup`）、协同、App Store 上架——等 Model → Layout → Metal 主链路跑通后再做。
