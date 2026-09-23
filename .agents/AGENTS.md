# YMind — Agent 说明

macOS 思维导图应用。技术栈：**Swift + SwiftUI（壳）+ Metal（画布）**。
第一版形态：**单窗口**、**中心辐射布局**。HTML 原型在 `prototype/`。

本仓库面向 Agent 的配置统一放在 **`.agents/`**（skills、MCP、rules），不绑定某一款 IDE。

另请阅读：[`.agents/rules/ymind-apple-stack.md`](rules/ymind-apple-stack.md)

## 强制约束：文档语言

**以后本仓库所有文档一律优先使用中文。**

包括但不限于：`AGENTS.md`、`.agents/rules/`、`docs/`、设计说明、架构笔记、PR 说明、变更记录。  
专有名词、API 名、命令、代码标识符可保留英文原文；正文叙述用中文。  
第三方 skill 原文不必改写；**我们自己新写或维护的文档必须中文优先。**

## MCP 与 Skill

| 层级 | 含义 | 位置 |
|------|------|------|
| **MCP 服务器** | Agent 可直接调用的工具（构建 / 运行 / 调试） | `.agents/mcp.json` |
| **Skills** | 使用工具前应阅读的指南 | `.agents/skills/` |
| **Rules** | 项目架构与 skill 路由 | `.agents/rules/` |

已配置的 MCP（请在各 Agent 客户端从 `.agents/mcp.json` 注册）：

1. **`XcodeBuildMCP`** — `xcodebuildmcp mcp`。优先用于 macOS 的构建 / 运行 / 测试 / 日志 / UI。工作流配置：仓库根目录 `.xcodebuildmcp/config.yaml`（工具自身约定）。
2. **`xcode`** — Apple IDE 桥接（`xcrun mcpbridge`）。需要已打开 Xcode（26.3+），并在 Intelligence 中允许外部 Agent。用于 IDE 状态、预览、Xcode 原生工具。

启动 MCP 时请以**仓库根目录为 cwd**，以便发现 `.xcodebuildmcp/config.yaml`。

名为 `xcodebuildmcp`、`xcodebuildmcp-cli`、`axiom-xcode-mcp` 的 skill 是**使用说明**，不是服务器本身。

## 项目 Skills（`.agents/skills/`）

通过 `npx skills` / 根目录 `skills-lock.json` 安装。需要时优先读 skill，不要仅靠通用记忆。

### 核心（常用）

| Skill | 何时使用 |
|-------|----------|
| `swiftui-expert-skill` | 编写 / 审阅 SwiftUI（avdlee） |
| `swiftui-pro` | SwiftUI 最佳实践审阅（twostraws） |
| `axiom-swiftui` | SwiftUI API 与模式（Axiom） |
| `axiom-macos` | macOS 窗口、菜单、AppKit 桥接、沙盒 |
| `macos-patterns` | 原生 macOS 模式（菜单、面板、快捷键） |
| `macos-development` | 更广的 macOS SwiftUI / AppKit 实践 |
| `macos-spm-app-packaging` | SwiftPM macOS 应用脚手架与打包 |

### Metal / 渲染（画布）

| Skill | 何时使用 |
|-------|----------|
| `metal-gpu` | Metal 管线、buffer/纹理、MetalKit；含 `references/metal-api-guide.md` |
| `metal-shader-expert` | MSL shader、TBDR、GPU 调试 / 性能向写法 |
| `axiom-graphics` | GPU 总路由：MTKView / CAMetalLayer、迁移、显示性能、可缩放渲染（子文档在 `axiom-graphics/skills/`） |
| `core-animation` | Core Animation；含 `CAMetalLayer` 等层与合成 |
| `axiom-games` | SpriteKit / SceneKit 等（YMind 2D 画布一般不用，仅对照） |

做画布时优先：`metal-gpu` → 写 shader 再读 `metal-shader-expert` → 窗口缩放 / 显示刷新读 `axiom-graphics` 内 `resizable-rendering.md` / `display-performance.md`。

### 构建 / 调试 / Xcode

| Skill | 何时使用 |
|-------|----------|
| `macos-build` | 用 `xcodebuild` 编译 / 排查 macOS 构建 |
| `xcodebuildmcp` / `xcodebuildmcp-cli` | 如何使用 XcodeBuildMCP 服务 / CLI |
| `axiom-xcode-mcp` | 如何使用 Apple 的 `xcrun mcpbridge` |
| `axiom-build` | 构建失败、崩溃日志、Xcode 环境 |
| `ios-debugger-agent` | 通过 XcodeBuildMCP 运行 / 调试 |
| `debugging-instruments` | Instruments 性能剖析 |
| `xcode-build-orchestrator` | 端到端 Xcode 构建优化 |
| `xcode-build-fixer` | 落实已批准的构建优化 |
| `xcode-project-analyzer` | 工程 / scheme / 脚本阶段构建审计 |
| `xcode-compilation-analyzer` | Swift 编译热点 / 类型检查耗时 |
| `xcode-build-benchmark` | 测量 clean / 增量构建耗时 |
| `spm-build-analysis` | SPM 依赖 / 模块化带来的构建成本 |

### 辅助

| Skill | 何时使用 |
|-------|----------|
| `swift-concurrency` / `axiom-concurrency` | async/await、actor、Swift 6 并发 |
| `axiom-performance` | 内存、Instruments、循环引用、性能排查 |
| `swift-testing-expert` | Swift Testing |
| `swiftui-ui-patterns` | 导航、状态接线、UI 结构 |
| `swiftui-performance-audit` | 卡顿、失效、List 身份 |
| `macos-design-guidelines` | 面向 macOS HIG 的 UI 决策 |
| `axiom-apple-docs` | 查阅 / 解释 Apple 文档与诊断信息 |

## 更新 Skills

```bash
npx skills update -p -y
# 或从 lockfile 恢复：
npx skills experimental_install
```

## 第一版明确不做

多文档（`DocumentGroup`）、协同、App Store 上架打磨——等 Model → Layout → Metal 主链路跑通后再做。
