---
name: ymind-design
description: YMind UI 设计规范。把功能/界面需求转化为符合 Apple HIG 的正式上线级 UI 设计：design token + 组件状态表 + HTML 原型三件套，供开发 agent 逐条实现。动效分 SwiftUI 层与 Metal 层；读图审稿委派 vision-inspector。实现 Apple 平台 UI 前、或设计新界面时使用。
---

# YMind UI 设计规范

YMind：macOS 思维导图应用（SwiftUI 壳 + Metal 画布 + 中心辐射布局）。本 skill 规定把功能/界面需求转成正式 UI 设计的程序性规范，供开发 agent 逐条实现。

## 硬约束（YMind 特有）

- **平台**：macOS 单窗口工具。适用 Mac 约定：菜单栏、工具栏、键盘快捷键、窗口管理。查 `macos-design-guidelines`。
- **画布是 Metal，不是纯 SwiftUI**。节点增删/选中动画、边过渡在 Metal 层；文字编辑浮层、菜单、对话框在 SwiftUI/AppKit 层。**这两层动效必须分开设计**。
- **中心辐射树布局**：根节点居中，一级子节点 `side`（左/右）。围绕此布局设计，不要套任意树布局。
- 设计必须**能在本仓库现有的 SwiftUI + Metal 中实现**。优先沿用仓库已有的 `prototype/` 与 `docs/` 约定，不要另立一套并行设计系统。
- 所有设计文档用**中文**书写（标识符、token、API 名可保留英文）。

## 必读技能——设计前先读

动手设计前加载并遵循以下技能：
- `macos-design-guidelines` — macOS 的 Apple HIG（菜单栏、工具栏、键盘、窗口管理）
- `swiftui-ui-patterns`、`swiftui-expert-skill` — 确保规格能落到真实 SwiftUI
- `design-system` — token 架构（primitive → semantic → component）
- `ui-ux-pro-max` — UX 智能、无障碍、排版/配色规则（`--stack swiftui`）
- `core-animation`、`metal-gpu` — 用于 Metal 层动效规格

## 输出：三件套

每个设计任务都产出以下三件，写入下述仓库路径。

### 1. Design tokens — `docs/design/design-tokens.md`
- 三层 token 架构：**primitive → semantic → component**。
- 覆盖：颜色（亮色**和**暗色）、排版、间距、圆角、阴影、描边。
- 绝不向开发者暴露裸 hex/px——只定义他们可直接消费的语义 token。

### 2. 组件规格 — `docs/design/components/<component>.md`
- 每个组件一个文件（如 `node.md`、`toolbar.md`、`inspector.md`、`context-menu.md`）。
- 每个组件给**状态表**：默认 / hover / active / disabled（相关处含 focus）。
- 每条规格引用语义 token（不写死数值）。列出开发者能逐行实现的确切行为。

### 3. 交互原型 — `prototype/design/*.html`
- 沿用现有 `prototype/` 约定，作为视觉/交互参考。
- 承载静态布局**和**动态动效/交互——动效在这里可视化呈现，而非仅文字描述。
- 标注为开发参考，非最终实现。

## 动效 tokens — `docs/design/motion-tokens.md`
- 定义动效 token：时长、缓动曲线、spring 参数、stagger。
- **分开** SwiftUI 层动效（浮层、菜单、对话框）与 Metal 层动效（节点增删/选中、边过渡）。实现层不同，约束不同。
- 尊重 macOS 的「减弱动态效果」（reduced-motion）偏好。

## 无障碍与平台合规
- 遵循 HIG 及类 WCAG 规则：对比度 ≥ 4.5:1、可键盘导航、焦点态、禁止无标签纯图标。
- macOS 菜单栏必须存在；所有功能必须能通过键盘快捷键触达。

## 读图（视觉审稿）
设计过程需要**读图**（审现有 UI 截图、核对原型渲染、对比视觉输出）时，**委派 `vision-inspector`**——不要凭文件名或上下文猜图内容。传给它的图必须是绝对路径，并附逐条编号的问题清单。`vision-inspector` 已钉视觉模型 `ark/glm-5.3-flash`。禁止臆造图片内容。

## 输出约定
- 返回精简总结：写入/更新了哪些文件、关键设计决策、留给用户的待定问题。
- 设计决策必须依据上述技能与仓库实际架构——不得发明约定。
- 若需求含糊或会违反 HIG/平台约束，指出冲突并提出符合 HIG 的替代方案，而不是默默猜测。
