# YMind 导出（PNG / Markdown）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 YMind 加两种导出：PNG 全展开整图（离屏 Metal 光栅化）与结构化 Markdown 标题大纲，经 NSSavePanel 落地，入口为工具条 + File 菜单。

**Architecture:** Model 层纯函数 `MarkdownExporter`/`ExportNaming`（Foundation only）生成 MD 与文件名；Render 层 `PNGExporter`（全展开复制 → RadialLayout → `MetalRenderer.renderImage` 离屏渲染）产出 PNG；`MetalRenderer` 把 `draw(in:)` 绘制体抽成 `encodeContent(...)` 供在线/离屏共用，并新增 `renderImage`。Shell 层 `DocumentWorkflow.exportMarkdown/exportPNG` 生成数据 + NSSavePanel 落地，工具条与 File 菜单双入口。导出不经过命令栈、不改文档、不动折叠态（FR-E4）。

**Tech Stack:** Swift 6、SwiftUI（工具条/菜单）、Metal（离屏渲染）、Swift Testing（`@Suite`/`@Test`）。无新 shader、无新第三方依赖。

**Spec:** `docs/superpowers/specs/2026-09-27-ymind-export-design.md`（本 plan 从 spec 论证；执行者需同时读 spec 与本文）。需求真源：`docs/prds/prd-ymind-export-2026-09-25/prd.md`。体验真源：`prototype/`（`treeToMarkdown`/`exportMarkdown`/`withFullyExpanded`/`paintExportCanvas`/`safeFilename`）。

## Global Constraints

（逐条取自 spec，所有 task 隐式包含本节）

- Markdown 语义（spec §3.1，PRD FR-E2）：先序遍历整树（含折叠枝）；根深度 1 → `#`，子 +1，`level = min(depth, 6)` 封顶 h6；文案 `\r\n→\n`、逐行 trim、去空行、join 空格；最终空 → 「未命名」；不输出 fill/side/collapsed 元数据。
- 文件名（spec §3.2，对齐原型 `safeFilename`）：非法字符 `\ / : * ? " < > |` → `_`；空白 run → 单空格；trim；48 字符截断；空 → 兜底 `ymind`。
- PNG 语义（spec §4，PRD FR-E3）：导出前**复制**文档并把所有 `collapsed` 清为 false（**不改原文档**）→ 全树布局 → 包围盒光栅化 → 恢复折叠态（画布 UI 不变）；不画分叉 ± 控件与交互 UI；纸面背景 `#e7e4dc`；`scale = min(max(2400/长边, 0.35), 2)` 长边 ≤2400px。
- `MetalRenderer` 重构不改变在线绘制行为与绘制顺序（spec §4.2）；`drawText`/`drawBranchToggles` 签名由 `view: MTKView` 改为 `displayScale: CGFloat`。
- 落地：NSSavePanel 选位置（spec §1.2 拍板），默认名 `ExportNaming.safeFilename(base: root.text, ext:)`。
- 入口：工具条按钮 + File 菜单「导出…」双入口（spec §1.2 拍板，FR-E1）。
- 导出**不经过 commandBus、不入 Undo、不写 `.ymind`、不动折叠态**（spec §6，FR-E4）。
- 边界：`ExportNaming` 在 **Model** 层（仅 Foundation）；`PNGExporter` 在 **Render** 层（import AppKit CoreGraphics Foundation MetalKit，均在白名单）；`scripts/check-boundaries.sh` 不得新增违规。
- 新增源码文件经 Xcode 同步组（`PBXFileSystemSynchronizedRootGroup`）自动纳入，**不改** `project.pbxproj`。
- 文档中文优先；专有名词/API 可英文。

---

### Task 1: Model — `MarkdownExporter`（纯函数，TDD）

**Files:**
- Create: `YMindApp/YMindApp/Model/MarkdownExporter.swift`
- Test: `YMindApp/YMindAppTests/MarkdownExporterTests.swift`

**Interfaces:**
- Consumes: 无（新类型）。读 `MindMapDocument`/`Node`（已有，`Model/MindMapDocument.swift`、`Model/Node.swift`）。
- Produces: `enum MarkdownExporter { static func markdown(from document: MindMapDocument) -> String }`、`static func collapsedText(_ text: String) -> String`（可测的文案规整；Task 1 内部用）。Task 5 依赖 `MarkdownExporter.markdown(from:)`。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/MarkdownExporterTests.swift
import Testing
import Foundation
@testable import YMindApp

@Suite("MarkdownExporter")
struct MarkdownExporterTests {
    private func doc(rootText: String = "中心", children: [Node] = []) -> MindMapDocument {
        var d = MindMapDocument.blank(rootText: rootText)
        d.root.children = children
        return d
    }

    @Test func rootOnly_singleHash() {
        #expect(MarkdownExporter.markdown(from: doc(rootText: "根")) == "# 根")
    }

    @Test func nestedDepth_addsHash() {
        var d = doc(rootText: "根", children: [Node(text: "一层")])
        d.root.children[0].children = [Node(text: "二层")]
        #expect(MarkdownExporter.markdown(from: d) == "# 根\n\n## 一层\n\n### 二层")
    }

    @Test func depthBeyondSix_cappedAtH6() {
        var node = Node(text: "最深层")
        for _ in 0..<6 { node = Node(text: "层", children: [node]) }
        var d = doc(rootText: "根")
        d.root.children = [node]
        let lines = MarkdownExporter.markdown(from: d).split(separator: "\n")
        #expect(lines.last!.hasPrefix("###### "))
        #expect(!lines.last!.hasPrefix("####### "))
    }

    @Test func collapsedBranch_stillFullyExported() {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, side: .right, children: [grand])
        #expect(MarkdownExporter.markdown(from: doc(children: [child])).contains("### 孙"))
    }

    @Test func multilineText_collapsedToSingleLine() {
        let md = MarkdownExporter.markdown(from: doc(rootText: "第一行\r\n第二行\n\n  第三行  "))
        #expect(md == "# 第一行 第二行 第三行")
    }

    @Test func emptyText_becomesUnnamed() {
        #expect(MarkdownExporter.markdown(from: doc(rootText: "   \n  ")) == "# 未命名")
    }

    @Test func fillAndSideMetadata_notEmitted() {
        let child = Node(text: "有填色", side: .left, fill: .sage)
        #expect(MarkdownExporter.markdown(from: doc(children: [child])) == "# 中心\n\n## 有填色")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/MarkdownExporterTests`
Expected: FAIL —— `MarkdownExporter` 未定义（编译错误）。

- [ ] **Step 3: 实现 `MarkdownExporter.swift`**

```swift
import Foundation

/// 整棵逻辑树 → Markdown 标题层级（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历，深度 d → min(d, 6) 个 `#`。
enum MarkdownExporter {
    /// 深度 1 = 中心主题；子节点 +1；超过 6 仍用 `######`。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        var lines: [String] = []
        walk(document.root, depth: 1, into: &lines)
        return lines.joined(separator: "\n\n")
    }

    private static func walk(_ node: Node, depth: Int, into lines: inout [String]) {
        let level = min(max(depth, 1), 6)
        lines.append("\(String(repeating: "#", count: level)) \(collapsedText(node.text))")
        for child in node.children {
            walk(child, depth: depth + 1, into: &lines)
        }
    }

    /// 对齐原型 treeToMarkdown：\r\n → \n，按行 trim，去空行，join 空格。
    static func collapsedText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "未命名" : collapsed
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（7 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/MarkdownExporter.swift YMindApp/YMindAppTests/MarkdownExporterTests.swift
git commit -m "feat: Markdown 导出纯函数（标题层级，忽略折叠）"
```

---

### Task 2: Model — `ExportNaming`（文件名规整，TDD）

**Files:**
- Create: `YMindApp/YMindApp/Model/ExportNaming.swift`
- Test: `YMindApp/YMindAppTests/MarkdownExporterTests.swift`（追加 `@Suite("ExportNaming")`）

**Interfaces:**
- Consumes: 无。
- Produces: `enum ExportNaming { static func safeFilename(base: String?, ext: String) -> String }`。Task 5 依赖。

- [ ] **Step 1: 追加失败测试（同一测试文件末尾）**

```swift
@Suite("ExportNaming")
struct ExportNamingTests {
    @Test func illegalCharacters_replaced() {
        #expect(ExportNaming.safeFilename(base: "a/b\\c:d", ext: "png") == "a_b_c_d.png")
    }
    @Test func whitespaceRuns_collapsedToSingleSpace() {
        #expect(ExportNaming.safeFilename(base: "  我的  图\n表 ", ext: "md") == "我的 图表.md")
    }
    @Test func emptyBase_fallsBackToYmind() {
        #expect(ExportNaming.safeFilename(base: "   ", ext: "png") == "ymind.png")
    }
    @Test func longBase_truncated() {
        let long = String(repeating: "a", count: 100)
        #expect(ExportNaming.safeFilename(base: long, ext: "md").hasPrefix(String(repeating: "a", count: 48)))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/ExportNamingTests`
Expected: FAIL —— `ExportNaming` 未定义。

- [ ] **Step 3: 实现 `ExportNaming.swift`**

```swift
import Foundation

/// 导出文件名规整（对齐原型 safeFilename）。仅字符串处理，无 UI 依赖。
enum ExportNaming {
    static func safeFilename(base: String?, ext: String) -> String {
        let illegal = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let name = (base ?? "ymind")
            .components(separatedBy: illegal)
            .joined(separator: "_")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = String(trimmed.prefix(48)).isEmpty ? "ymind" : String(trimmed.prefix(48))
        return "\(finalName).\(ext)"
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（4 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/ExportNaming.swift YMindApp/YMindAppTests/MarkdownExporterTests.swift
git commit -m "feat: 导出文件名规整 safeFilename（对齐原型）"
```

---

### Task 3: Render — `MetalRenderer` 重构（抽取 `encodeContent`，无行为变化）

**Files:**
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`（`draw(in:)` 方法体、`drawText`、`drawBranchToggles`）

**Interfaces:**
- Consumes: 无新依赖。读既有 `ViewportUniforms`/`Camera`/`LayoutSnapshot`/`NodeFrame`/`DropIntent`。
- Produces: `private func encodeContent(into encoder: MTLRenderCommandEncoder, viewportSize: CGSize, snapshot: LayoutSnapshot, camera: Camera, displayScale: CGFloat, selectedIds: Set<UUID>, selectionAnchorId: UUID?, cutSourceIds: Set<UUID>, intent: DropIntent?, searchHitId: UUID?, marquee: CGRect?)`；`drawText`/`drawBranchToggles` 改收 `displayScale: CGFloat`。Task 4 的 `renderImage` 调用 `encodeContent`。

- [ ] **Step 1: 抽取 `draw(in:)` 绘制体为 `encodeContent`**

把 `draw(in:)` 中从 `guard let encoder = ...` 到 `encoder.endEncoding()` 之前的全部内容（含 `var viewport = ViewportUniforms(...)` 与 9 个 `draw*` 调用）抽成 `private func encodeContent(...)`，签名见上。`draw(in:)` 改为：

```swift
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.label = "YMind 画布"

        encodeContent(
            into: encoder,
            viewportSize: view.bounds.size,
            snapshot: snapshot,
            camera: camera,
            displayScale: view.window?.backingScaleFactor ?? 1,
            selectedIds: selectedIds,
            selectionAnchorId: selectionAnchorId,
            cutSourceIds: cutSourceIds,
            intent: intent,
            searchHitId: searchHitId,
            marquee: marquee
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
```

`encodeContent` 内保持原绘制顺序：边 → 节点底色 → 文字 → 分叉控件 → 多选描边 → 剪切弱化 → 放置反馈 → 搜索高亮 → 框选。

- [ ] **Step 2: 改 `drawText` / `drawBranchToggles` 签名**

`drawText` 与 `drawBranchToggles` 的 `view: MTKView` 参数改为 `displayScale: CGFloat`；函数体内删掉 `let displayScale = view.window?.backingScaleFactor ?? 1` 这行，直接用参数。`rasterScale = displayScale * Self.rasterBucket(camera.scale)` 保持不变。两处调用点改传 `displayScale: displayScale`。

- [ ] **Step 3: 构建 + 跑既有测试（无行为变化）**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。
Run: `xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/RadialLayoutTests -only-testing:YMindAppTests/CanvasInteractionTests`
Expected: PASS（回归确认渲染相关测试不受影响）。

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/Render/MetalRenderer.swift
git commit -m "refactor: MetalRenderer 抽 encodeContent，在线/离屏共用绘制体"
```

---

### Task 4: Render — `PNGExporter` + `MetalRenderer.renderImage`（离屏光栅化）

**Files:**
- Create: `YMindApp/YMindApp/Render/PNGExporter.swift`
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`（新增 `renderImage`）
- Test: `YMindApp/YMindAppTests/PNGExporterTests.swift`

**Interfaces:**
- Consumes: `encodeContent`（Task 3）、`RadialLayout.layout`/`TextMeasure`（已有）、`MetalRenderer`（已有）。
- Produces: `enum PNGExporter { static func data(document: MindMapDocument, maxDimension: CGFloat = 2400, padding: CGFloat = 48) -> Data?; static func fullyExpanded(_ document: MindMapDocument) -> MindMapDocument; static var paperColor: NSColor }`；`MetalRenderer.renderImage(snapshot:contentBounds:maxDimension:padding:paper:) -> CGImage?`。Task 5 依赖 `PNGExporter.data(document:)`。

- [ ] **Step 1: 在 `MetalRenderer.swift` 末尾（`renderImage` 前/后均可，类内）新增 `renderImage`**

```swift
    /// 导出：把 `contentBounds` 以 `scale = min(2, maxDimension / 长边)` 光栅化到离屏纹理，
    /// 仅画边/节点块/文字/填色（不画分叉 ± 与交互 UI），返回 CGImage。
    func renderImage(
        snapshot: LayoutSnapshot,
        contentBounds: CGRect,
        maxDimension: CGFloat = 2400,
        padding: CGFloat = 48,
        paper: NSColor
    ) -> CGImage? {
        guard !contentBounds.isNull, !contentBounds.isEmpty else { return nil }

        let contentW = max(contentBounds.width, 1)
        let contentH = max(contentBounds.height, 1)
        let scale = min(max(maxDimension / max(contentW, contentH), 0.35), 2)
        let pixelW = max(Int(ceil((contentW + padding * 2) * scale)), 1)
        let pixelH = max(Int(ceil((contentH + padding * 2) * scale)), 1)

        var camera = Camera()
        camera.scale = scale
        camera.translation = CGPoint(
            x: padding - contentBounds.minX * scale,
            y: padding - contentBounds.minY * scale
        )

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelW,
            height: pixelH,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        let background = rgba(paper)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: Double(background.w)
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        encoder.label = "YMind 导出"

        // 导出固定按浅色纸面解析动态语义色，结果与系统外观无关。
        let appearance = NSAppearance(named: .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            encodeContent(
                into: encoder,
                viewportSize: CGSize(width: pixelW, height: pixelH),
                snapshot: snapshot,
                camera: camera,
                displayScale: 1,
                selectedIds: [],
                selectionAnchorId: nil,
                cutSourceIds: [],
                intent: nil,
                searchHitId: nil,
                marquee: nil
            )
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let region = MTLRegionMake2D(0, 0, pixelW, pixelH)
        var bytes = [UInt8](repeating: 0, count: pixelW * pixelH * 4)
        texture.getBytes(&bytes, bytesPerRow: pixelW * 4, from: region, mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: pixelW,
                height: pixelH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: pixelW * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return image
    }
```

> 说明：bgra8Unorm 内存布局为 B,G,R,A（little-endian），与 `byteOrder32Little | premultipliedFirst` 的 CGImage 一致；纹理行 0 = 顶行，与 CGImage 行 0 = 顶行一致，无需翻转。

- [ ] **Step 2: 创建 `PNGExporter.swift`**

```swift
import AppKit
import CoreGraphics
import Foundation
import MetalKit

/// 全展开整图 PNG 导出（FR-E3）。
/// 流程：记录折叠态 → 全部展开 → 布局 → 按包围盒离屏光栅化 → 恢复折叠态。
/// 不改原文档、不入 Undo（FR-E4）。
enum PNGExporter {
    /// 生成 PNG 数据；失败返回 nil。
    static func data(
        document: MindMapDocument,
        maxDimension: CGFloat = 2400,
        padding: CGFloat = 48
    ) -> Data? {
        let expanded = fullyExpanded(document)
        let snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())
        let bounds = snapshot.frames.values.reduce(CGRect.null) { $0.union($1.rect) }
        guard !bounds.isNull,
              let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        do {
            let renderer = try MetalRenderer(device: device)
            guard let image = renderer.renderImage(
                snapshot: snapshot,
                contentBounds: bounds,
                maxDimension: maxDimension,
                padding: padding,
                paper: paperColor
            ) else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: image)
            return rep.representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }

    /// 复制文档并把所有 `collapsed` 清为 false（不改原文档）。
    static func fullyExpanded(_ document: MindMapDocument) -> MindMapDocument {
        var doc = document
        func expand(_ node: inout Node) {
            node.collapsed = false
            for index in node.children.indices {
                expand(&node.children[index])
            }
        }
        expand(&doc.root)
        return doc
    }

    /// 纸面背景（对齐原型 #e7e4dc）。
    static var paperColor: NSColor {
        NSColor(srgbRed: 0xE7 / 255, green: 0xE4 / 255, blue: 0xDC / 255, alpha: 1)
    }
}
```

- [ ] **Step 3: 写 PNG 冒烟测试**

```swift
// YMindAppTests/PNGExporterTests.swift
import Testing
import AppKit
@testable import YMindApp

@Suite("PNGExporter")
struct PNGExporterTests {
    @Test func fullyExpanded_clearsAllCollapsed_andKeepsOriginal() {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, children: [grand])
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = [child]

        let expanded = PNGExporter.fullyExpanded(d)
        #expect(expanded.root.children[0].collapsed == false)
        #expect(expanded.root.children[0].children[0].collapsed == false)
        // 原文档折叠态不变
        #expect(d.root.children[0].collapsed == true)
    }

    @Test func data_rendersPNG_whenMetalAvailable() throws {
        // 无 Metal 设备的环境跳过（macOS 测试宿主通常有）。
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw SkipConfirmationError.testSkipped
        }
        var d = MindMapDocument.blank(rootText: "根")
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, fill: .sage, children: [grand])
        d.root.children = [child]

        let data = PNGExporter.data(document: d)
        #expect(data != nil)
        // PNG 魔数
        let sig = data?.prefix(8)
        #expect(sig == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // 折叠态仍保持（FR-E3 验收 1：导后折叠仍在）
        #expect(d.root.children[0].collapsed == true)
    }
}
```

> 若测试框架无 `SkipConfirmationError`，用 `#require(MTLCreateSystemDefaultDevice() != nil)` 前置条件替代（Swift Testing 支持 `#require` 跳过）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/PNGExporterTests`
Expected: PASS。若有 Metal 环境，`data_rendersPNG_whenMetalAvailable` 验证 PNG 魔数与折叠态不变。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Render/PNGExporter.swift YMindApp/YMindApp/Render/MetalRenderer.swift YMindApp/YMindAppTests/PNGExporterTests.swift
git commit -m "feat: PNG 全展开整图离屏导出（MetalRenderer.renderImage + PNGExporter）"
```

---

### Task 5: Shell — `DocumentWorkflow` 导出 + File 菜单

**Files:**
- Modify: `YMindApp/YMindApp/YMindAppApp.swift`（`DocumentWorkflow` 增两方法；`DocumentCommands` 增菜单组）

**Interfaces:**
- Consumes: `MarkdownExporter.markdown(from:)`（Task 1）、`PNGExporter.data(document:)`（Task 4）、`ExportNaming.safeFilename(base:ext:)`（Task 2）、`DocumentSession`（已有）。
- Produces: `@MainActor static func exportMarkdown(_ session: DocumentSession)`、`@MainActor static func exportPNG(_ session: DocumentSession)`（同文件内 `DocumentWorkflow`）。Task 6 的工具条按钮调用这两个方法。

- [ ] **Step 1: `DocumentWorkflow` 增导出方法（放 `saveAs` 之后、`confirmReplacement` 之前）**

```swift
    /// 导出 Markdown（FR-E2）：生成纯结构标题大纲，SavePanel 落地。
    static func exportMarkdown(_ session: DocumentSession) {
        session.commitEditingIfNeeded()
        let text = MarkdownExporter.markdown(from: session.model.document)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = ExportNaming.safeFilename(
            base: session.model.document.root.text,
            ext: "md"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    /// 导出 PNG（FR-E3）：全展开整图，SavePanel 落地。
    static func exportPNG(_ session: DocumentSession) {
        session.commitEditingIfNeeded()
        guard let data = PNGExporter.data(document: session.model.document) else {
            session.errorMessage = "导出 PNG 失败：无法生成图像"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ExportNaming.safeFilename(
            base: session.model.document.root.text,
            ext: "png"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
```

> `YMindAppApp.swift` 已 `import UniformTypeIdentifiers`，`.plainText`/`.png` 可用。

- [ ] **Step 2: `DocumentCommands` 增菜单组（`saveItem` 组之后）**

```swift
        CommandGroup(after: .saveItem) {
            Button("导出 Markdown…") {
                DocumentWorkflow.exportMarkdown(session)
            }
            Button("导出 PNG…") {
                DocumentWorkflow.exportPNG(session)
            }
        }
```

- [ ] **Step 3: 构建确认**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/YMindAppApp.swift
git commit -m "feat: 导出入口 — DocumentWorkflow + File 菜单（Markdown/PNG）"
```

---

### Task 6: Shell — 工具条导出按钮

**Files:**
- Modify: `YMindApp/YMindApp/App/MainToolbar.swift`
- Modify: `YMindApp/YMindApp/ContentView.swift`

**Interfaces:**
- Consumes: `DocumentWorkflow.exportMarkdown/exportPNG`（Task 5）。
- Produces: 工具条两个按钮（`导出 Markdown`/`导出 PNG`），点击触发导出。无后续依赖。

- [ ] **Step 1: `MainToolbar` 增闭包参数与按钮**

`MainToolbar` 结构体加两个存储属性（放在 `setFill` 之后）：

```swift
    let exportMarkdown: () -> Void
    let exportPNG: () -> Void
```

在 `secondaryAction` 组的 `fit` 按钮之后追加：

```swift
            Divider()

            Button(action: exportMarkdown) {
                Label("导出 Markdown", systemImage: "doc.plaintext")
            }
            .help("导出 Markdown 大纲")

            Button(action: exportPNG) {
                Label("导出 PNG", systemImage: "square.and.arrow.up")
            }
            .help("导出全展开 PNG 整图")
```

- [ ] **Step 2: `ContentView` 接闭包（`MainToolbar(...)` 调用处，`setFill` 之后）**

```swift
                    setFill: { fill in session.setFill(fill) },
                    exportMarkdown: { DocumentWorkflow.exportMarkdown(session) },
                    exportPNG: { DocumentWorkflow.exportPNG(session) }
```

- [ ] **Step 3: 构建确认**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。

- [ ] **Step 4: 手测（对齐 PRD §6 验收 1–5）**

Run 应用（`xcodebuild` 产物或 Xcode），造一棵含折叠枝、多行文案、有填色的树：
1. 点工具条「导出 PNG」→ SavePanel → 存盘 → 打开 PNG 确认含折叠枝内节点、有填色、整图完整；回画布确认折叠态未变（验收 1、4）。
2. 点「导出 MD」→ 存盘 → 打开确认标题层级与树深一致（验收 2）。
3. File 菜单「导出 Markdown…/导出 PNG…」同样可触发（验收 FR-E1）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/App/MainToolbar.swift YMindApp/YMindApp/ContentView.swift
git commit -m "feat: 工具条导出按钮（Markdown/PNG）"
```

---

### Task 7: 收尾 — 全量验证 + 边界 + 文档

**Files:**
- Verify: 全量测试、`scripts/check-boundaries.sh`。
- Modify: `docs/架构现状.md`（如需登记新文件）、`docs/prds/prd-ymind-export-2026-09-25/prd.md`（status draft → 已实现，若仓库有此惯例）。

**Interfaces:**
- Consumes: 全部前面任务。
- Produces: 可交付的完整功能。

- [ ] **Step 1: 全量构建 + 测试**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 全部测试 PASS（既有 + 新增 `MarkdownExporterTests`/`ExportNamingTests`/`PNGExporterTests`）。

- [ ] **Step 2: 边界校验**

Run: `scripts/check-boundaries.sh`
Expected: 输出「依赖边界检查通过」，退出码 0。`MarkdownExporter.swift`/`ExportNaming.swift`（Model，仅 Foundation）、`PNGExporter.swift`（Render，AppKit/CoreGraphics/Foundation/MetalKit）均不违规。

- [ ] **Step 3: 更新 PRD status 与架构现状（若仓库惯例要求）**

按 `docs/prds/` 现状把 `prd-ymind-export-2026-09-25/prd.md` 的 `status: draft` 改为 `status: 已实现`（若其他已实现 PRD 有同样标记）；`docs/架构现状.md` 如需登记导出入口，补一行说明（不改边界白名单，因无新依赖）。

- [ ] **Step 4: Commit**

```bash
git add docs/prds/prd-ymind-export-2026-09-25/prd.md docs/架构现状.md
git commit -m "docs: 导出增量状态回写（PRD 已实现）"
```

---

## Self-Review 记录

- **Spec 覆盖：** §3（Markdown/命名）→ Task 1、2；§4（PNG + renderer 重构）→ Task 3、4；§5（入口/落地）→ Task 5、6；§6（错误/边界）→ Task 5 的 `errorMessage` + Task 4 测试；§7（验收）→ Task 4/6/7。
- **占位符：** 无 TBD/TODO；每个代码步骤含完整可复制代码。
- **类型一致性：** `MarkdownExporter.markdown(from:)`、`PNGExporter.data(document:)`、`ExportNaming.safeFilename(base:ext:)`、`encodeContent(...)`、`renderImage(...)` 在各 Task 的 Consumes/Produces 与代码中签名一致。
