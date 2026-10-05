# Linva Apple 技术栈指引

Linva 是 **macOS** 思维导图应用：SwiftUI 壳 + Metal 画布 + 中心辐射树模型。
HTML 原型在 `prototype/`（仅作交互 / 布局参考；一旦开始原生开发，以原生代码为准）。

## 强制约束：文档语言

本仓库文档**优先使用中文**（与 `.agents/AGENTS.md` 一致）。专有名词与 API 可保留英文。

## 实现 Apple 平台代码之前

先阅读 `.agents/skills/` 下对应 skill（有适用 skill 时，不要仅凭记忆编造平台 API）：

| 任务 | Skill 目录 |
|------|------------|
| SwiftUI 视图、状态、审阅 | `swiftui-expert-skill`、`swiftui-pro`、`axiom-swiftui` |
| macOS 窗口 / 菜单 / AppKit 桥接 | `axiom-macos`、`macos-development`、`macos-patterns` |
| Metal / MTKView / shader / GPU 绘制 | `metal-gpu`、`metal-shader-expert`、`axiom-graphics`（及其 `skills/metal-migration*.md`、`resizable-rendering.md`、`display-performance.md`） |
| CAMetalLayer / 层合成 | `core-animation`、`axiom-graphics` |
| 脚手架 / SwiftPM macOS 打包 | `macos-spm-app-packaging` |
| 并发 / actor / MainActor | `swift-concurrency`、`axiom-concurrency` |
| 单元测试（Swift Testing） | `swift-testing-expert` |
| HIG / macOS UI 约定 | `macos-design-guidelines` |
| 用 `xcodebuild` CLI 编译 | `macos-build` |
| 通过 **MCP** 构建 / 运行 / 调试 | 优先 MCP 服务 `XcodeBuildMCP`（见 `.agents/mcp.json`）；用法见 skill `xcodebuildmcp` |
| Xcode IDE MCP（预览 / IDE 状态） | MCP 服务 `xcode`（`xcrun mcpbridge`）；用法见 skill `axiom-xcode-mcp` |
| 构建失败 / 崩溃 / Xcode 环境 | `axiom-build` |
| 构建过慢 / SPM / 编译热点 | `xcode-build-orchestrator`、`spm-build-analysis`、`xcode-compilation-analyzer` |
| 运行时性能 / Instruments | `axiom-performance`、`debugging-instruments`、`swiftui-performance-audit` |
| 查阅 Apple API 文档 | `axiom-apple-docs` |
| SwiftUI 模式 / 失效 | `swiftui-ui-patterns`、`swiftui-performance-audit` |

## 架构不变量（v1）

- 先做单窗口工具（暂不做 DocumentGroup）。
- 模型：树结构；根节点 + 一级子节点的 `side`（left / right）。
- 布局：CPU 做中心辐射 → 得到 frame / 边；Metal 只负责绘制。
- 文字编辑：SwiftUI / AppKit 浮层，不做 Metal IME。
- 先验证 Model + Layout，再加深 Metal。

## 依赖边界（已强制）

分层依赖由 `scripts/check-boundaries.sh` 在构建时强制（build phase「依赖边界校验」，违规即红）。白名单：

- Model / Commands：仅 `Foundation`
- Layout：`Foundation AppKit CoreGraphics CoreText`
- Session：`Foundation Combine CoreGraphics`
- Render：`Foundation AppKit CoreGraphics Metal MetalKit SwiftUI simd`
- App：`Foundation AppKit SwiftUI`

新增依赖必须同步更新脚本白名单与 `docs/架构现状.md` §5。

## 原型

移植到原生时，以 `prototype/index.html` 与 `app.js` 作为已约定的交互与布局参考。
