# YMind A/D 配色落地 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 YMind 画布视觉从现状（直角矩形、系统蓝根节点、separator 连线、暖纸导出）对齐到已定案的 A/D token（亮=系统原生 / 暗=深色沉浸）。

**Architecture:** 改动集中在 Render 层（`MetalRenderer` 画布底色/节点/连线/圆角）与 `NodeFillStyle`（动态 `NSColor` 派生）与 `LayoutConstants`（padding）。根节点字体已是 SF 加粗（18.4pt bold），无需改。布局测试引用 `LayoutConstants` 常量，改值不破坏。

**Tech Stack:** Swift / SwiftUI + Metal（MTLRenderPipeline 实色/纹理管线），Xcode 26.3+。

**Spec:** [docs/design/design-tokens.md](../../../docs/design/design-tokens.md)（A/D 定案，§6 映射清单）

## Global Constraints

- 不暴露裸 hex 到 Swift 视图层：颜色全部经 `NodeFillStyle` 动态 `NSColor`（`appearanceAware`）派生，亮暗随外观解析。
- Render 层只消费 `LayoutSnapshot + Camera`，不得访问 Model（ymind-layout-snapshot 不变量）。
- 文字纹理坐标系：保留 `TextTextureRasterizer.flipVertically`（ymind-render-text 红线），本次不触碰。
- 根节点文字色保持 `.white`（`frame.isRoot ? .white : .labelColor` 现状），根底亮暗均深/彩、白字可读。
- PNG 导出底固定亮 `#ececec`（品牌一致，不随外观）。
- 全部文档中文。

---

## Task 1: NodeFillStyle 新增动态 token（根底 / 连线 / 画布暗色）

**Files:**
- Modify: `YMindApp/YMindApp/Render/NodeFillStyle.swift`

**Interfaces:**
- Consumes: 无（自包含）
- Produces: `NodeFillStyle.rootDefault()` → NSColor（亮 `#3a3a3c` / 暗 `#0a84ff`）、`NodeFillStyle.line()` → NSColor（亮 `#c7c7cc` / 暗 `#3a3a3e`）、`NodeFillStyle.canvasBackground()` → NSColor（亮 = `windowBackgroundColor` / 暗 `#171719`）

**实现说明：** `appearanceAware` 私有 helper 已存在（hue/s/b 或 RGB 均可）。新增三个 static 方法，用 `NSColor(name:nil) { appearance in ... }` 按外观解析固定 RGB。

- [ ] **Step 1: 在 `NodeFillStyle` 添加 `rootDefault()`**

```swift
/// 无填色根节点底（A/D token）：亮 = 深中性 #3a3a3c，暗 = accent 蓝 #0a84ff。
static func rootDefault() -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x0A/255, green: 0x84/255, blue: 0xFF/255, alpha: 1)
            : NSColor(srgbRed: 0x3A/255, green: 0x3A/255, blue: 0x3C/255, alpha: 1)
    }
}
```

- [ ] **Step 2: 添加 `line()` 连线色**

```swift
/// 连线（A/D token）：亮 #c7c7cc，暗 #3a3a3e。
static func line() -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x3A/255, green: 0x3A/255, blue: 0x3E/255, alpha: 1)
            : NSColor(srgbRed: 0xC7/255, green: 0xC7/255, blue: 0xCC/255, alpha: 1)
    }
}
```

- [ ] **Step 3: 添加 `canvasBackground()` 画布底**

```swift
/// 画布底（A/D token）：亮 = 系统 windowBackgroundColor，暗 = #171719。
static func canvasBackground() -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x17/255, green: 0x17/255, blue: 0x19/255, alpha: 1)
            : NSColor.windowBackgroundColor
    }
}
```

- [ ] **Step 4: 验证编译**

Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 编译通过（NodeFillStyle 新方法无报错）。

---

## Task 2: LayoutConstants padding 对齐 token

**Files:**
- Modify: `YMindApp/YMindApp/Layout/LayoutConstants.swift`

**Interfaces:**
- Consumes: 无
- Produces: 更新常量值（`nodePadY` 10→12、`rootPadX` 22→20）；其余不变

**说明：** 布局测试引用 `LayoutConstants.nodePadY`/`rootPadX` 常量本身（`RadialLayoutTests` 用 `LayoutConstants.nodePadY * 2`、`LogicLayoutTests` 用 `LayoutConstants.rootPadX`），改值自动跟随，不破坏。

- [ ] **Step 1: 改两个常量**

```swift
static let rootPadX: CGFloat = 20   // 22 → 20（--s-root-pad-x）
static let nodePadY: CGFloat = 12   // 10 → 12（--s-node-pad-y）
```

- [ ] **Step 2: 跑布局测试**

Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/RadialLayoutTests -only-testing:YMindAppTests/LogicLayoutTests`
Expected: 全绿（常量引用自动跟随）。

---

## Task 3: MetalRenderer 画布底色 / 连线色 / 根底

**Files:**
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`（`draw` clearColor、`edgeVertices`、`fillVertices`）

**Interfaces:**
- Consumes: Task 1 的 `NodeFillStyle.line()`、`NodeFillStyle.canvasBackground()`、`NodeFillStyle.rootDefault()`
- Produces: 无（纯渲染）

- [ ] **Step 1: 画布 clearColor 用动态色**

在 `draw(in:snapshot:camera:...)` 顶部：

```swift
let background = rgba(NodeFillStyle.canvasBackground())
descriptor.colorAttachments[0].clearColor = MTLClearColor(
    red: Double(background.x),
    green: Double(background.y),
    blue: Double(background.z),
    alpha: Double(background.w)
)
```

（原代码用 `rgba(NSColor.windowBackgroundColor)`，替换为 `NodeFillStyle.canvasBackground()`。）

- [ ] **Step 2: 连线色用 `NodeFillStyle.line()`**

在 `edgeVertices(snapshot:visibleIds:camera:)` 内：

```swift
let color = rgba(NodeFillStyle.line())
```

（原 `rgba(.separatorColor)`。）

- [ ] **Step 3: 无填色根节点底用 `NodeFillStyle.rootDefault()`**

在 `fillVertices(frames:camera:)` 的 else 分支：

```swift
} else {
    let color = rgba(
        frame.isRoot
            ? NodeFillStyle.rootDefault()
            : NSColor.controlBackgroundColor
    )
    return rectangleQuad(rect: rect, color: color)
}
```

（原 `NSColor.controlAccentColor`。）

- [ ] **Step 4: 验证编译**

Run: `xcodebuild build ...`（同 Task 1）
Expected: 编译通过。

---

## Task 4: 节点/根节点圆角

**Files:**
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`（`fillVertices`、新增 `roundedRectVertices`）

**Interfaces:**
- Consumes: 无
- Produces: `roundedRectVertices(rect:radius:color:) -> [SolidVertex]`

**说明：** 现状节点直角矩形（`rectangleQuad`）。按 token 节点圆角 8pt、根 10pt。参照既有 `pillVertices`（半高圆角）泛化为指定 `radius`。

- [ ] **Step 1: 新增 `roundedRectVertices`**

```swift
/// 圆角矩形（指定 radius，屏空间像素）。
private func roundedRectVertices(
    rect: CGRect,
    radius: CGFloat,
    color: SIMD4<Float>
) -> [SolidVertex] {
    let r = min(radius, min(rect.width, rect.height) / 2)
    guard r > 0.5 else { return rectangleQuad(rect: rect, color: color) }
    var vertices = rectangleQuad(
        rect: CGRect(x: rect.minX + r, y: rect.minY, width: max(rect.width - r * 2, 0), height: rect.height),
        color: color
    )
    vertices += rectangleQuad(
        rect: CGRect(x: rect.minX, y: rect.minY + r, width: rect.width, height: max(rect.height - r * 2, 0)),
        color: color
    )
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: rect.minX + r, y: rect.minY + r), .pi),
        (CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2),
        (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0),
        (CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2),
    ]
    for (center, startAngle) in corners {
        for index in 0..<4 {
            let first = startAngle + CGFloat(index) * .pi / 8
            let second = startAngle + CGFloat(index + 1) * .pi / 8
            vertices += [
                solidVertex(x: center.x, y: center.y, color: color),
                solidVertex(x: center.x + cos(first) * r, y: center.y + sin(first) * r, color: color),
                solidVertex(x: center.x + cos(second) * r, y: center.y + sin(second) * r, color: color),
            ]
        }
    }
    return vertices
}
```

- [ ] **Step 2: `fillVertices` 全部填充路径改用圆角**

`fillVertices` 内所有 `rectangleQuad(rect: rect, color:)` 换成圆角调用，按节点/根区分半径：

```swift
// 根节点（填色/无填色）：radius = 10 * camera.scale
// 普通节点（填色/无填色）：radius = 8 * camera.scale
let radius = (frame.isRoot ? 10 : 8) * camera.scale
```

替换 `fillVertices` 内 3 处填充矩形（根填色、普通填色底、无填色底）。注意：普通节点填色的**边框描边** `strokeVertices` 保持直角（描边绕圆角节点的近似，v1 不新增圆角 stroke）。

- [ ] **Step 3: 验证编译**

Run: `xcodebuild build ...`
Expected: 编译通过。

---

## Task 5: PNG 导出底对齐（暖纸 → 亮系统灰）

**Files:**
- Modify: `YMindApp/YMindApp/Render/PNGExporter.swift`

**Interfaces:**
- Consumes: 无
- Produces: `PNGExporter.paperColor` = 亮 `#ececec`

- [ ] **Step 1: 改 `paperColor`**

```swift
/// 导出底（亮系统灰 #ececec，固定不随外观）。
static var paperColor: NSColor {
    NSColor(srgbRed: 0xEC / 255, green: 0xEC / 255, blue: 0xEC / 255, alpha: 1)
}
```

（原 `#e7e4dc` 暖纸。）

- [ ] **Step 2: 验证 PNG 导出测试**

Run: `xcodebuild test ... -only-testing:YMindAppTests/PNGExporterTests`
Expected: 全绿（测试若断言底色则随新值更新——先跑看结果）。

---

## Task 6: 构建 + 手测亮暗两态

**Files:** 无（验证）

- [ ] **Step 1: 全量构建**

Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 成功。

- [ ] **Step 2: 跑全部单测**

Run: `xcodebuild test ...`
Expected: 全绿。

- [ ] **Step 3: 运行 App 目测**

启动 App：确认亮色画布 = 系统灰、根节点深中性 `#3a3a3c` 白字、节点圆角 8、连线浅灰；切系统深色 → 画布近黑 `#171719`、根节点 accent 蓝、连线深灰。节点文字清晰、无翻转/模糊（ymind-render-text 回归点）。

---

## Self-Review

- **Spec 覆盖**：design-tokens.md §6 映射清单 → 画布 clearColor（T3）、连线色（T3）、节点 padding/圆角（T2/T4）、根节点底（T3）、PNG 导出底（T5）、根字体已是 SF 加粗（无需任务，Global Constraints 说明）。✓
- **Placeholder**：无 TBD/TODO。✓
- **类型一致**：`NodeFillStyle.line()` / `.canvasBackground()` / `.rootDefault()` 三处引用一致；`roundedRectVertices(rect:radius:color:)` 唯一签名。✓
- **范围**：选中描边/搜索命中描边保持直角（现状），不做圆角 stroke（v1 近似，注释说明）。
