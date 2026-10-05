# Linva 组件规格 — 工具条（Toolbar）

> 层级：**SwiftUI 壳**。工具条是画布的次要命令面（主命令在菜单栏，`macos-design-guidelines`）。已拍板：**收敛常用 + 溢出其余**——只留高频操作，剪贴板/改侧/导出移入菜单与右键菜单。色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 结构（收敛后的工具条）

统一标题栏 + 工具条风格（`.unified`），`ToolbarItemGroup` 分组。

| 位置 | 内容 | 说明 |
|------|------|------|
| 前导 | 文档标题（`principal` 或窗口标题兜底） | 跟随 `WindowStateBridge` 同步 |
| **primaryAction** | 节点操作组：**子主题 / 同级主题 / 删除** | 高频树编辑 |
| **primaryAction** | 填色色点组（`FillSwatchesView`） | 高频分类表达 |
| **secondaryAction** | 画布工具（选择⇄手型 segmented）+ 缩放（− % + 适应） | 视图高频 |
| **secondaryAction** | 溢出菜单（`ToolbarOverflowMenu`） | 低频命令收纳 |
| 状态 | 选中计数（`已选 N`） | 多选时显示 |

> **已收敛出工具条**（仍可从菜单栏/右键触达）：剪切/复制/粘贴、移到左/右侧、导出 Markdown/PNG。这些在 `LinvaAppApp` 的 `DocumentCommands` 与右键菜单中保留快捷键（⌘X/C/V、⌘←/⌘→、导出菜单项）。

---

## 2. 按钮状态表

| 状态 | 背景 | 文字/图标 | 动效 |
|------|------|----------|------|
| **默认** | 透明 | `sem.color.text.primary` | — |
| **hover** | `prim.color.node` @ 92% | 同 | `motion.duration.fast` |
| **按下(active)** | `sem.color.accent.soft` | 同 | `fast`，按压 `translateY(1px)` |
| **disabled** | 透明 | opacity 0.35 | 无 |

- 删除用 `.danger` hover（`sem.color.danger` 淡底 + 色字）。
- 工具条按钮 `ToolbarItem`，`.help(...)` 提供快捷键提示（现状已全量标注）。

---

## 3. 填色色点组（FillSwatchesView）

> 现状实现即规格：5 色 + 默认清除（斜线）。

| 状态 | 色点 | 边框 | 动效 |
|------|------|------|------|
| 默认 | `prim.color.fill.*` 对应色 | `ink 18%` 1.5pt | — |
| hover | 同 | 同 | `scale 1.08`（fast） |
| 激活 | 同 | `sem.color.accent` 2pt 外环（+2pt 表面隔环） | `motion.duration.base` |
| 默认清除 | `surface.node` + 斜线 `prim.color.danger` | 同 | — |
| disabled | opacity 0.35 | — | — |

- 无选中时全禁用；多选 fill 不一致时无激活态。

---

## 4. 画布工具 + 缩放

| 控件 | 形式 | 值 |
|------|------|-----|
| 画布工具 | `.segmented` Picker（cursorarrow ⇄ hand.draw） | `canvasTool` 会话态 |
| 缩小 | `minus.magnifyingglass` 按钮 | 缩放 1/1.12 |
| 缩放 % | `monospacedDigit` 文本（min 44pt） | 随 camera |
| 放大 | `plus.magnifyingglass` 按钮 | 缩放 ×1.12 |
| 适应 | `arrow.up.left.and.arrow.down.right` 按钮 | `camera.fit` |

---

## 5. 溢出菜单（ToolbarOverflowMenu）

> 收纳低频命令，`.toolbar { ToolbarItem(placement: .automatic) { ToolbarOverflowMenu {...} } }`（macOS 15+）。内容：剪切/复制/粘贴、移到左侧/右侧、导出 Markdown/导出 PNG。溢出项与菜单栏命令共用同一 `CommandBus` 用例，禁用态同步。

---

## 6. 无障碍 / 合规

- 图标按钮一律 `.accessibilityLabel(...)` + `.help(...)`（禁止无标签纯图标，HIG 11.1）。
- 工具条是「次要命令面」：主命令在菜单栏 + 快捷键（HIG 1.1 / 5.1）。
- 所有功能键盘可触达。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：收敛工具条（primaryAction 高频 + secondaryAction 视图 + 溢出菜单），低频命令移菜单栏/右键；锚定 `MainToolbar` / `FillSwatchesView` / `DocumentCommands` |
