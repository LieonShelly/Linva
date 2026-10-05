# Linva — Agent 说明

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

**Linva 专属技能（本仓库自建，不在 lockfile 管理）—— 改核心代码前优先读：**

| Skill | 何时使用 |
|-------|----------|
| `linva-pm` | 需求探索 / 痛点分析 / 外部调研（Google·X·竞品）/ 找下一个 idea / 写 PRD 之前的思考。产出需求文档 + HTML 原型图，正式 PRD 交 bmad-prd |
| `linva-command` | 新增/修改改变树结构的命令（CommandBus + Undo） |
| `linva-codec-version` | 改 `.linva` schema、节点字段、序列化/版本升迁 |
| `linva-layout-snapshot` | 扩展布局算法 / NodeFrame / EdgeGeometry / Render-Layout 接缝 |
| `linva-render-text` | 文字纹理、TextAtlas、坐标系/Retina/缓存 |
| `linva-design` | 正式 UI 设计 / 视觉改版：产出 Apple HIG 合规的「design token + 组件状态表 + HTML 原型」三件套，动效分 SwiftUI/Metal 层，读图委派 vision-inspector |

**第三方 skill**（`npx skills` 安装，各自 `SKILL.md` 的 `description` 自动路由）：
- 完整路由表见 **[`.agents/rules/linva-apple-stack.md`](rules/linva-apple-stack.md)**（实现 Apple 平台代码前先查）。
- 画布优先序：`metal-gpu` → `metal-shader-expert` → `axiom-graphics`（`resizable-rendering.md` / `display-performance.md`）。

## 子代理（pi-subagents，nicobailon 版）

Agent 定义文件在 `.agents/agents/*.md`（nicobailon/pi-subagents 自动发现，字段如 `systemPromptMode`/`inheritSkills`/`defaultContext`）。**注意：不是 `tintinweb/pi-subagents`，那是另一个包，字段不同。**

> 设计能力已提炼为 skill `linva-design`（见上表），不另设 designer subagent——设计是迭代式工作，留在主会话上下文更契合。真正需要隔离/钉模型时才用 subagent。

| Agent | 何时委派 |
|-------|----------|
| `vision-inspector` | 需分析图片内容（见下方「视觉委派」）。钉死视觉模型 `ark/glm-5.3-flash` |

## 基础约束

### 代码检索（强制）— codegraph MCP

**代码检索一律用 CodeGraph MCP（`codegraph_explore`），不得用文本方式（grep / Glob / Read 逐文件）人工翻代码兜底。**

- 索引位于 **`LinvaApp/.codegraph`**（SQLite：`codegraph.db`）。
- 因仓库根不在索引根，**每次调用必须显式传 `projectPath: "LinvaApp"`**（或 `LinvaApp/.codegraph` 往上可达的路径），否则服务器无默认项目、答不了。
- 一次 `codegraph_explore` 返回符号源 + 调用路径 + 波及面，替代「grep + Read 循环」。

**必须用**：问符号/功能怎么工作、定位 bug/找字段/定义与调用方、改动前定波及范围、调查代码区/架构。

**例外（可用常规工具）**：查目录结构/文件名/待检索清单（`glob`/`read` 目录）、纯文本层级匹配/Mermaid/文档内容、项目无索引或索引缺失时用内置工具（Read/Grep/Glob）完成——**不要擅自跑索引**，索引属用户决策。

> 详细：`.agents/rules/linva-code-retrieval.md`

### 视觉委派（触发条件）— vision delegate

需分析**图片内容**且满足任一条时，委派视觉子代理（模型 `ark/glm-5.3-flash`）：

1. 父会话看不到图——读图返回占位 `[image/png]` 却无法描述，或用户消息内嵌图报"无法处理"；
2. 图多/大/需精读（截图走查、逐元素对比、图表读数、图内 OCR），精读挤占父上下文；
3. 需客观盲测式描述——父会话已持有预期答案，自己看图易被污染。

**启动优先序**：① `task` + `delegate` 子代理（继承 `ark/glm-5.3-flash`，`read` 读图得内联图像）；② `xd://subagent` + `vision-inspector`（需 `pi` CLI，当前本机缺，暂不可用）；③ 兜底父会话直接 `read`（实测当前主模型能看图，失败即转 ①）。

**任务模板防幻觉必填**：图片绝对路径 + 逐条编号问题清单 + 明示「只报告实际可见内容，禁止凭文件名/上下文猜测；看不到答 `CANNOT_SEE: <原因>`」+ 结构化输出（逐图 `## <路径>` + 要点）。**禁止**把预期答案写进任务（污染盲测，`task` 的 `context` 字段同样不得泄露）。

**证据红线**：视觉结论必须来自子代理真实读图，不得从路径/文件名/会话上下文推断。

> 详细与验证记录：`.agents/rules/linva-vision-delegate.md`

### 图形

流程图 / 类图 / 架构图优先用 **Mermaid**。

## Claude 常犯的错误（犯两次就写进这里）

- **改树绕过命令栈** → Undo 失真。改树必走 `commandBus.execute(...)`；相机/选中/搜索态不入栈。见 `linva-command`。
- **改 `.linva` schema 不递增 `currentVersion`、不写迁移** → 老文件打不开。见 `linva-codec-version`。
- **深层节点带 `side`** → side 只存根下一层，`sanitize` 会强制清掉。见 `linva-codec-version`。
- **改文字渲染删掉行翻转** → 文字颠倒/错位。保留 `TextTextureRasterizer.flipVertically`。见 `linva-render-text`。
- **Render 层去读 Model** → Metal 只消费 `LayoutSnapshot`，不懂树。见 `linva-layout-snapshot`。
- **新增依赖没进 `scripts/check-boundaries.sh` 白名单** → 构建即红。新依赖同步更新白名单与 `docs/架构现状.md` §5。

## 更新 Skills

```bash
npx skills update -p -y
# 或从 lockfile 恢复：
npx skills experimental_install
```

## 第一版明确不做

多文档（`DocumentGroup`）、协同、App Store 上架——等 Model → Layout → Metal 主链路跑通后再做。
