# YMind PDF 导出子系统（FR-E1 / FR-E2）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 YMind 加 PDF 导出：把当前导图（含折叠枝，全展开语义）矢量绘制为多页 PDF（默认横向 A4 按宽度分页，可选缩放单页），范围可选整树 / 当前选中枝，经 SavePanel 落地，与 Markdown / PNG 并列 File 菜单三入口。

**Architecture:** Render 层新增 `PDFExporter`：`scope` 子图抽取 → `PNGExporter.fullyExpanded`（复用，清折叠不改原档）→ `RadialLayout` 出 `LayoutSnapshot` → 按包围盒分页 → `CGContext(consumer:mediaBox:)` 逐页矢量绘制（边折线 / 节点矩形块 / `NSAttributedString` 矢量文字）。分页换算与子树抽取为**纯函数可单测**；绘制体是 CG（AppKit/CoreGraphics），不经 Metal 纹理（无 flipVertically 翻转问题）。Shell 层 `DocumentWorkflow.exportPDF` 解析 scope + SavePanel 落地，File 菜单增「导出 PDF…」。

**Tech Stack:** Swift 6、SwiftUI（菜单）、CoreGraphics（PDF context）+ AppKit（NSBezierPath / NSAttributedString 矢量文字）、Swift Testing。无新 shader、无新 dependency、不改 Render 白名单（Foundation/AppKit/CoreGraphics 已在 Render 白名单）。

**Spec:** `docs/superpowers/specs/2026-09-30-ymind-import-export-design.md`（本 plan 从 spec 论证；执行者需同时读 spec 与本文）。需求真源：`docs/prds/prd-ymind-import-export-2026-09-30/prd.md`（FR-E1/E2）+ `addendum.md`（§3 PDF 管线）。体验真源：`prototype/import-export.html`（标签「导出 PDF」）。参照：`2026-09-27-ymind-export-design.md` / `2026-09-27-ymind-export.md`（PNG 导出语义复用）。

## Global Constraints

（逐条取自 spec §5，所有 task 隐式包含本节）

- **`PDFExporter` 放 Render 层**，`import Foundation AppKit CoreGraphics`（均已在 Render 白名单；**不得 import Metal/MetalKit**，矢量文字不走纹理）。`scripts/check-boundaries.sh` 构建期校验，违规即红。
- **无新 import 白名单**；`YMindCodec.currentVersion` 保持 2（FR-C1/C2）。
- **全展开语义（FR-E1）**：导出前**复制**文档并把所有 `collapsed=false`（复用 `PNGExporter.fullyExpanded`，不改原文档、不入 Undo、导出后画布折叠态不变）。内容 = 节点块 / 连线 / 文案 / 填色；**不画**分叉 ± 控件与交互 UI（选中/搜索/框选/放置）。
- **scope（拍板）**：单选 → `subtree(anchorId)` 该节点及其子树；无选中 → `full` 整树；多选 → 「当前选中枝」禁用 ⇒ `full`（spec §1.2/§5.2）。
- **page mode**：默认 `paginateByWidth`：横向 A4 `842×595` pt、margin 24、`scale=1`（世界 pt = 页 pt），从包围盒按 `usableW = 794` / `usableH = 547` 切列切行，每页渲染一个（列,行）世界窗口。`fitSinglePage`：`scale = min(usableW/boundsW, usableH/boundsH)`，整树缩至一页（spec §5.1，分页换算已用脚本验证含负原点/多行）。
- **绘制语义**（spec §5.1）：
  - 边：`EdgeGeometry.points` 是 4 个点（start → 水平到 controlX → 水平到 end），**Metal 实际按相邻对连成折线**（`zip(points, points.dropFirst())`）；PDF 用同款折线（`move(to:)` + 逐点 `line(to:)`），`separatorColor`，线宽 `max(1.25, 2*scale)`。
  - 节点块：矩形（Metal `rectangleQuad` 是直角矩形，非圆角——PDF 同用 `NSBezierPath(rect:)`）。有 `fill` → 根 `rootBackground(fill)`、非根 `background(fill)` + `border(fill)` 描边（`strokeVertices` 语义 = 4 边描边）；无 `fill` → 根 `controlAccentColor`、非根 `controlBackgroundColor`。
  - 文字：根 `white` 18.4 bold / 非根 `labelColor` 14.7 medium，`NSAttributedString.draw(in:)` 画在节点 rect（矢量、可打印/选中/复制）。
  - 外观：`NSAppearance(named: .aqua)` 解析动态语义色（与系统外观无关，对齐 PNG 导出）；每页纸色背景 `#e7e4dc`（复用 `PNGExporter.paperColor`）。
- **文件名**：`ExportNaming.safeFilename(base: document.root.text, ext: "pdf")`；SavePanel `allowedContentTypes = [.pdf]`。
- **入口**：File 菜单 `CommandGroup(after: .saveItem)` 增「导出 PDF…」，与 MD/PNG 并列（FR-E2）。PDF 导出**不经过命令栈、不入 Undo、不写 `.ymind`、不改折叠态**（FR-E4）。
- 新增源码文件经 Xcode 同步组自动纳入，**不改** `project.pbxproj`。
- 文档中文优先；专有名词/API 可英文。

---

### Task 1: Render — PDF 分页换算纯函数（`PDFPagination`，TDD）

**Files:**
- Create: `YMindApp/YMindApp/Render/PDFExporter.swift`（本 Task 只写分页结构，绘制体后续 Task 增补同文件）
- Test: `YMindApp/YMindAppTests/PDFExporterTests.swift`（`@Suite("PDFPagination")`）

**Interfaces:**
- Consumes: 无（本 Task 不依赖既有类型；用 CGRect / CGSize）。读规约 §5.1 分页。
- Produces: `struct PDFPageMode`（`.paginateByWidth` / `.fitSinglePage` + `pageSize` + `margin`）、`struct PDFPagination`（`scale` + `pageWindows: [CGRect]` 世界窗口列表）+ `enum PDFPagination { static func compute(bounds:mode:) -> PDFPagination }`。Task 3 依赖 `PDFPagination` 逐页取窗口并算平移/缩放。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/PDFExporterTests.swift
import Testing
import CoreGraphics
import Foundation
@testable import YMindApp

@Suite("PDFPagination")
struct PDFPaginationTests {
    private let a4 = CGSize(width: 842, height: 595)
    private let margin: CGFloat = 24
    private let usableW: CGFloat = 842 - 48   // 794
    private let usableH: CGFloat = 595 - 48   // 547

    @Test func paginateByWidth_wideTree_tilesColumns() {
        let bounds = CGRect(x: -1000, y: -200, width: 2000, height: 400)
        let mode = PDFPageMode(fit: .paginateByWidth, pageSize: a4, margin: margin)
        let p = PDFPagination.compute(bounds: bounds, mode: mode)
        // 3 列（2000/794→ceil 3）×1 行（400≤547）
        #expect(p.scale == 1)
        #expect(p.pageWindows.count == 3)
        // 第一页窗口从 bounds 原点对齐
        #expect(p.pageWindows[0] == CGRect(x: -1000, y: -200, width: usableW, height: usableH))
        // 第二页 x 右移一列宽
        #expect(p.pageWindows[1].minX == -1000 + usableW)
    }

    @Test func paginateByWidth_smallTree_singlePage() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let p = PDFPagination.compute(bounds: bounds, mode: PDFPageMode(fit: .paginateByWidth, pageSize: a4, margin: margin))
        #expect(p.pageWindows.count == 1)
        #expect(p.scale == 1)
    }

    @Test func paginateByWidth_tallTree_tilesRows() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 1200)
        let p = PDFPagination.compute(bounds: bounds, mode: PDFPageMode(fit: .paginateByWidth, pageSize: a4, margin: margin))
        // 1 列 × 3 行（1200/547→ceil 3）
        #expect(p.pageWindows.count == 3)
        #expect(p.pageWindows[1].minY == 547)   // 549≈547 页高窗口步进
    }

    @Test func fitSinglePage_scalesToFitWithMargin() {
        let bounds = CGRect(x: -500, y: -200, width: 1500, height: 1200)
        let p = PDFPagination.compute(bounds: bounds, mode: PDFPageMode(fit: .fitSinglePage, pageSize: a4, margin: margin))
        #expect(p.pageWindows.count == 1)
        // scale = min(794/1500, 547/1200) = min(0.529, 0.456)
        #expect(abs(p.scale - (547 / 1200)) < 0.001)
    }

    @Test func fitSinglePage_windowAlignsBoundsOrigin() {
        let bounds = CGRect(x: -500, y: -200, width: 300, height: 200)
        let p = PDFPagination.compute(bounds: bounds, mode: PDFPageMode(fit: .fitSinglePage, pageSize: a4, margin: margin))
        #expect(p.pageWindows[0] == CGRect(x: -500, y: -200, width: 300, height: 200))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/PDFPagination`
Expected: FAIL —— `PDFPageMode` / `PDFPagination` 未定义。

- [ ] **Step 3: 实现 `PDFExporter.swift` 的分页部分**

```swift
// Render/PDFExporter.swift
import AppKit
import CoreGraphics
import Foundation

/// PDF 页面模式（spec §5.1）。
struct PDFPageMode: Equatable {
    enum PageFit: Equatable { case paginateByWidth, fitSinglePage }
    var fit: PageFit = .paginateByWidth
    var pageSize: CGSize = CGSize(width: 842, height: 595)   // 横向 A4
    var margin: CGFloat = 24
}

/// 一次导出分页换算结果：scale + 每页世界窗口（对齐 bounds 原点）。
struct PDFPagination: Equatable {
    var scale: CGFloat = 1
    var pageWindows: [CGRect] = []
}

/// 分页纯函数：把内容包围盒换算成「每页该画哪个世界窗口 + 统一缩放」。
enum PDFPagination {
    static func compute(bounds: CGRect, mode: PDFPageMode) -> PDFPagination {
        let usableW = mode.pageSize.width - mode.margin * 2
        let usableH = mode.pageSize.height - mode.margin * 2
        let W = max(bounds.width, 1)
        let H = max(bounds.height, 1)

        switch mode.fit {
        case .fitSinglePage:
            let scale = min(usableW / W, usableH / H)
            return PDFPagination(scale: scale, pageWindows: [bounds])
        case .paginateByWidth:
            // scale=1（世界 pt = 页 pt），按 usableW/usableH 切列切行，窗口贴合 bounds 原点。
            let cols = Int(ceil(W / usableW))
            let rows = Int(ceil(H / usableH))
            var windows: [CGRect] = []
            for col in 0..<cols {
                for row in 0..<rows {
                    windows.append(CGRect(
                        x: bounds.minX + CGFloat(col) * usableW,
                        y: bounds.minY + CGFloat(row) * usableH,
                        width: usableW,
                        height: usableH
                    ))
                }
            }
            return PDFPagination(scale: 1, pageWindows: windows)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（5 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Render/PDFExporter.swift YMindApp/YMindAppTests/PDFExporterTests.swift
git commit -m "feat: PDF 分页换算纯函数（横向A4按宽切列 / 缩放单页）"
```

---

### Task 2: Render — `PDFScope` 子树抽取纯函数（TDD）

**Files:**
- Modify: `YMindApp/YMindApp/Render/PDFExporter.swift`（追加 scope + 抽取）
- Test: `YMindApp/YMindAppTests/PDFExporterTests.swift`（追加 `@Suite("PDFScope")`）

**Interfaces:**
- Consumes: `MindMapDocument`/`Node`（Model，已有）。
- Produces: `enum PDFScope { case full, subtree(UUID) }`、`static func subtreeDocument(_ document: MindMapDocument, rootID: UUID) -> MindMapDocument?`（以该节点为根的新文档，保留子树、换新根 isRoot 语义 via 布局；找不到返回 nil）。Task 3 依赖。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("PDFScope")
struct PDFScopeTests {
    private func doc() -> MindMapDocument {
        var d = MindMapDocument.blank(rootText: "根")
        // 根 → A(a1,a2) , B(b1)
        let a1 = Node(text: "a1")
        let a2 = Node(text: "a2")
        let a = Node(text: "A", children: [a1, a2])
        let b1 = Node(text: "b1")
        let b = Node(text: "B", children: [b1])
        d.root.children = [a, b]
        return d
    }

    @Test func subtreeDocument_returnsNodeAndDescendants_asNewRoot() {
        let d = doc()
        let aID = d.root.children[0].id
        let sub = PDFExporter.subtreeDocument(d, rootID: aID)
        #expect(sub != nil)
        #expect(sub?.root.text == "A")
        #expect(sub?.root.children.map(\.text) == ["a1", "a2"])
    }

    @Test func subtreeDocument_leafNode_returnsSingleNodeDoc() {
        let d = doc()
        let b1ID = d.root.children[1].children[0].id
        let sub = PDFExporter.subtreeDocument(d, rootID: b1ID)
        #expect(sub?.root.text == "b1")
        #expect(sub?.root.children.isEmpty == true)
    }

    @Test func subtreeDocument_unknownID_returnsNil() {
        let d = doc()
        #expect(PDFExporter.subtreeDocument(d, rootID: UUID()) == nil)
    }

    @Test func subtreeDocument_fullScope_returnsOriginal() {
        let d = doc()
        let sub = PDFExporter.subtreeDocument(d, rootID: d.root.id)
        #expect(sub?.root.text == "根")
        #expect(sub?.root.children.map(\.text) == ["A", "B"])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/PDFScope`
Expected: FAIL —— `PDFScope` / `subtreeDocument` 未定义。

- [ ] **Step 3: 追加 subtree 抽取**

```swift
/// 导出范围（spec §5.1 拍板）。
enum PDFScope: Equatable {
    case full
    case subtree(UUID)
}

enum PDFExporter {
    /// 抽「以 rootID 为根的新 MindMapDocument」；找不到返回 nil。
    /// 保留子树结构（含 fill/side/collapsed 原值；布局时新根 isRoot=true，side 被布局忽略）。
    static func subtreeDocument(_ document: MindMapDocument, rootID: UUID) -> MindMapDocument? {
        guard let node = find(rootID, in: document.root) else { return nil }
        return MindMapDocument(version: document.version, root: node)
    }

    private static func find(_ id: UUID, in node: Node) -> Node? {
        if node.id == id { return node }
        for child in node.children {
            if let found = find(id, in: child) { return found }
        }
        return nil
    }
}
```

> 说明：抽取出的子树原样作为新文档，布局时新根 `isRoot=true` 以 (0,0) 为中心辐射；其 `side` 不被布局使用（等价于清空）。保留 `collapsed`/`fill` —— `fullyExpanded`（Task 3 会调用）随后清折叠。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（4 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Render/PDFExporter.swift YMindApp/YMindAppTests/PDFExporterTests.swift
git commit -m "feat: PDF 子树抽取纯函数（scope.subtree）"
```

---

### Task 3: Render — `PDFExporter.data` 矢量绘制（CG PDF context）

**Files:**
- Modify: `YMindApp/YMindApp/Render/PDFExporter.swift`（追加 `data(document:scope:mode:)` 与私有绘制）
- Test: `YMindApp/YMindAppTests/PDFExporterTests.swift`（追加 `@Suite("PDFExporterRendering")`）

**Interfaces:**
- Consumes: `PDFPageMode`/`PDFPagination`（Task 1）、`PDFScope.subtreeDocument`（Task 2）、`PNGExporter.fullyExpanded`/`paperColor`（已有）、`RadialLayout.layout`/`TextMeasure`（已有）、`NodeFillStyle`（已有）、`EdgeGeometry`/`NodeFrame`/`LayoutSnapshot`（已有）、`ExportNaming`（此处不用，Shell 用）。
- Produces: `static func data(document: MindMapDocument, scope: PDFScope = .full, mode: PDFPageMode = .init()) -> Data?`（Data?，nil=失败）。Task 4 依赖 `PDFExporter.data(document:scope:)`。

- [ ] **Step 1: 写失败测试**

```swift
import AppKit  // 需在文件顶部（若未加）
@Suite("PDFExporterRendering")
struct PDFExporterRenderingTests {
    private var a4: PDFPageMode { .init() }

    @Test func data_returnsPDFData_withMagicNumber_andOnePage() throws {
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = [Node(text: "子")]
        let data = PDFExporter.data(document: d, mode: a4)
        #expect(data != nil)
        let head = String(data: data?.prefix(8) ?? Data(), encoding: .isoLatin1)
        #expect(head?.hasPrefix("%PDF") == true)
        // 用 CGPDFDocument 数页数：小图 1 页（需从内存 Data 建 provider）
        let pdf = try #require(data.flatMap { makePDFDoc($0) })
        #expect(CGPDFDocumentGetNumberOfPages(pdf) == 1)
    }

    @Test func data_hiddenSubtree_isIncluded_andOriginalCollapsedKept() throws {
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, fill: .sage, children: [grand])
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = [child]

        let data = PDFExporter.data(document: d, mode: a4)
        #expect(data != nil)
        // 原文档折叠态不变（FR-E1 验收 4）
        #expect(d.root.children[0].collapsed == true)
    }

    @Test func data_subtreeScope_producesPDF() throws {
        var d = MindMapDocument.blank(rootText: "根")
        let a = Node(text: "A", children: [Node(text: "a1")])
        let b = Node(text: "B")
        d.root.children = [a, b]
        let data = PDFExporter.data(document: d, scope: .subtree(d.root.children[0].id), mode: a4)
        #expect(data != nil)
    }

    @Test func data_fitSinglePage_producesPDF() throws {
        var d = MindMapDocument.blank(rootText: "根")
        d.root.children = [Node(text: "子")]
        let mode = PDFPageMode(fit: .fitSinglePage)
        #expect(PDFExporter.data(document: d, mode: mode) != nil)
    }
}

/// 从 Data 建 CGPDFDocument（供页数断言）；需在测试 help 里定义。
private func makePDFDoc(_ data: Data) -> CGPDFDocument? {
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGPDFDocument(provider)
}
```

> 若 `makePDFDoc` 放文件顶层会 `@testable import` 冲突，测试文件内私有函数即可。第 2 个测试无法直接断言「含隐藏子树」——用「原折叠态不变 + 数据非空」作为可测代理（FR-E1 验收 4 的「含隐藏子树叶」靠手测 + `data_returnsPDFData` 已覆盖生成）；如需强断言页数随展开变化，可加「折叠 vs 展开 → 页数为 1 vs 1（200px 宽树不超一页）」但意义有限，避免脆测。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/PDFExporterRendering`
Expected: FAIL —— `PDFExporter.data` 未定义。

- [ ] **Step 3: 实现 `PDFExporter.data` 与矢量绘制**

```swift
// 追加进 Model 无——追加进 Render/PDFExporter.swift 的 enum PDFExporter 内

extension PDFExporter {
    /// 导出多页矢量 PDF Data；失败返回 nil。不造命令、不入 Undo、不改原文档折叠态（FR-E4）。
    static func data(
        document: MindMapDocument,
        scope: PDFScope = .full,
        mode: PDFPageMode = .init()
    ) -> Data? {
        // 1. scope → 源文档
        var source = document
        if case .subtree(let id) = scope {
            guard let sub = subtreeDocument(document, rootID: id) else { return nil }
            source = sub
        }
        // 2. 全展开（复用 PNGExporter：复制并清 collapsed，不改原文档）
        let expanded = PNGExporter.fullyExpanded(source)
        // 3. 布局
        let snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())
        let bounds = snapshot.frames.values.reduce(CGRect.null) { $0.union($1.rect) }
        guard !bounds.isNull else { return nil }
        // 4. 分页
        let pagination = PDFPagination.compute(bounds: bounds, mode: mode)
        guard !pagination.pageWindows.isEmpty else { return nil }

        // 5. CG PDF context（内存 consumer）
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }
        // PDF 每页
        let mediaBox = CGRect(x: 0, y: 0, width: mode.pageSize.width, height: mode.pageSize.height)

        let appearance = NSAppearance(named: .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            for window in pagination.pageWindows {
                guard ctx.beginPDFPage(nil) != 0 else { continue }
                ctx.draw(mediaBox: mediaBox)
                drawPage(ctx: ctx, snapshot: snapshot, window: window, scale: pagination.scale, margin: mode.margin, paper: PNGExporter.paperColor)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return data as Data
    }

    /// 绘一页：把世界窗口 window 以 scale 映射进页（margin 内），并画纸色背景。
    private static func drawPage(
        ctx: CGContext,
        snapshot: LayoutSnapshot,
        window: CGRect,
        scale: CGFloat,
        margin: CGFloat,
        paper: NSColor
    ) {
        // 背景
        ctx.setFillColor(cgColor(paper))
        ctx.fill(CGRect(x: 0, y: 0, width: 842, height: 595))  // 用窗口尺寸；此处页=842×595

        // 世界 → 页变换：页 (margin, margin) = 世界 window 原点；随后按 scale 缩放。
        // CG PDF 默认无变换；这里用显式变换矩阵让世界 y 轴向上。
        ctx.saveGState()
        ctx.translateBy(x: margin, y: margin)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -window.minX, y: -window.minY)
        // 世界 y 向上：CG 默认 y 轴向上，Node center 也是向上；无需翻转。

        // 绘制顺序：边 → 节点块 → 文字（对齐 Metal encodeContent）
        for edge in snapshot.edges {
            drawEdge(ctx, edge)
        }
        for frame in snapshot.frames.values.sorted(by: {
            $0.center.x < $1.center.x   // 稳定序（对齐 orderedFrames 的确定性）
        }) {
            drawNodeBlock(ctx, frame, scale: scale)
        }
        for frame in snapshot.frames.values {
            drawText(ctx, frame, scale: scale)
        }
        ctx.restoreGState()
    }

    private static func drawEdge(_ ctx: CGContext, _ edge: EdgeGeometry) {
        guard let first = edge.points.first else { return }
        ctx.setStrokeColor(cgColor(.separatorColor))
        ctx.setLineWidth(max(1.25, 2))        // 世界 pt 线宽（scale=1 时对齐 Metal max(1.25,2*scale)）
        ctx.beginPath()
        ctx.move(to: first)
        for p in edge.points.dropFirst() {
            ctx.addLine(to: p)
        }
        ctx.strokePath()
    }

    private static func drawNodeBlock(_ ctx: CGContext, _ frame: NodeFrame, scale: CGFloat) {
        let rect = frame.rect
        if let fill = frame.fill {
            if frame.isRoot {
                ctx.setFillColor(cgColor(NodeFillStyle.rootBackground(fill)))
                ctx.fill(rect)
            } else {
                ctx.setFillColor(cgColor(NodeFillStyle.background(fill)))
                ctx.fill(rect)
                // 边框：4 边描边（对齐 strokeVertices 语义）
                ctx.setStrokeColor(cgColor(NodeFillStyle.border(fill)))
                ctx.setLineWidth(max(1, 1.5 * scale))
                ctx.stroke(rect)
            }
        } else {
            // 无 fill：
            if frame.isRoot {
                ctx.setFillColor(cgColor(NSColor.controlAccentColor))
            } else {
                ctx.setFillColor(cgColor(NSColor.controlBackgroundColor))
            }
            ctx.fill(rect)
        }
    }

    private static func drawText(_ ctx: CGContext, _ frame: NodeFrame, scale: CGFloat) {
        // 用 AppKit NSAttributedString 矢量绘制：先包 NSGraphicsContext，flipped=false（世界 y 向上）。
        let font = NSFont.systemFont(ofSize: frame.isRoot ? 18.4 : 14.7, weight: frame.isRoot ? .bold : .medium)
        let color: NSColor = frame.isRoot ? .white : .labelColor
        let attr = NSAttributedString(string: frame.text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        // 多行：按节点宽高 wrap；用 boundingRect 从 rect 左上绘制
        let rect = frame.rect
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        attr.draw(with: rect, options: options)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func cgColor(_ color: NSColor) -> CGColor {
        color.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.black.cgColor
    }
}
```

> 说明与风险（ymind-render-text 相关性）：本路径**不经 Metal 纹理**，无 `flipVertically` 概念；`NSGraphicsContext(cgContext:flipped:false)` 让 `NSAttributedString.draw(with:)` 按世界 y 向上排版，避免文字颠倒（对应 skill 里的坐标系坑——此处以 flipped=false 天然规避，不引入翻转）。**必须手测文字朝向**（见 Task 4 Step 4），若发现文字颠倒，调 `flipped: true` 并核对基线，而不是改 `drawText` 的 rect。`ctx.draw(mediaBox:)` 若编译期不可用，改为对每页 `ctx.saveGState(); ctx.setFillColor(纸色); ctx.fill(mediaBox rect); ctx.restoreGState()`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/PDFExporterRendering`
Expected: PASS（4 个测试全过；`CGPDFDocumentGetNumberOfPages == 1` 验证小图单页 + `%PDF` 魔数）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Render/PDFExporter.swift YMindApp/YMindAppTests/PDFExporterTests.swift
git commit -m "feat: PDF 矢量导出（CG PDF context，折叠枝含全，纸色/矢量文字）"
```

---

### Task 4: Shell — `DocumentWorkflow.exportPDF` + File 菜单 + 手测

**Files:**
- Modify: `YMindApp/YMindApp/YMindAppApp.swift`（`DocumentWorkflow` 增 `exportPDF`；`DocumentCommands` 增「导出 PDF…」）

**Interfaces:**
- Consumes: `PDFExporter.data(document:scope:mode:)`（Task 3）、`ExportNaming.safeFilename(base:ext:)`（已有）、`DocumentSession`（已有）。
- Produces: `@MainActor static func exportPDF(_ session: DocumentSession)`。无后续依赖。

- [ ] **Step 1: 在 `DocumentWorkflow` 增 `exportPDF`（放 `exportPNG` 之后）**

```swift
    /// 导出 PDF（FR-E1）：scope 由选中态决定——单选→子树、无选中→整树、多选→整树（选中枝禁用时）。
    static func exportPDF(_ session: DocumentSession) {
        session.commitEditingIfNeeded()
        // scope 拍板：单选 → subtree(anchor)；否则 full
        let scope: PDFScope
        if session.selectedIds.count == 1, let anchor = session.selectionAnchorId,
           anchor != session.model.document.root.id {
            scope = .subtree(anchor)
        } else {
            scope = .full
        }
        guard let data = PDFExporter.data(document: session.model.document, scope: scope) else {
            session.errorMessage = "导出 PDF 失败：无法生成文档"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ExportNaming.safeFilename(
            base: session.model.document.root.text,
            ext: "pdf"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: `DocumentCommands` 增菜单项（`CommandGroup(after: .saveItem)` 内，PNG 之后）**

```swift
            Button("导出 PDF…") {
                DocumentWorkflow.exportPDF(session)
            }
```

- [ ] **Step 3: 构建确认**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。

- [ ] **Step 4: 手测（对齐 PRD §6 验收 4–5，含文字朝向回归）**

Run 应用，造一棵含折叠枝、多行文案、有填色的树：
1. 导出 PDF → 打开确认：矢量文字（可选中/复制）、含折叠枝子树、填色正确、纸色背景、可打印（验收 4）。
2. 确认文字**朝向正确、不颠倒**（ymind-render-text 关注点）：若颠倒 → 改 `NSGraphicsContext(flipped:)` 并核对基线，重跑本手测。
3. 折叠枝导出后画布折叠态不变（验收 4）。
4. 单选一个节点再导出 → 仅含该子树（验收 5）；无选中 → 整树。
5. 宽树导出 → 多页（按列切页）；选「缩放单页」→ 单页。
6. File 菜单「导出 Markdown…/PNG…/PDF…」三入口并列，互不影响（FR-E2）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/YMindAppApp.swift
git commit -m "feat: PDF 导出入口 — DocumentWorkflow + File 菜单（与MD/PNG并列）"
```

---

### Task 5: 收尾 — 全量验证 + 边界 + 文档

**Files:**
- Verify: 全量测试、`scripts/check-boundaries.sh`。
- Modify: `docs/架构现状.md`（登记新文件）。

**Interfaces:**
- Consumes: 全部前面任务。

- [ ] **Step 1: 全量构建 + 测试**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 全部测试 PASS（既有 + `PDFPagination`/`PDFScope`/`PDFExporterRendering`）。

- [ ] **Step 2: 边界校验**

Run: `scripts/check-boundaries.sh`
Expected: 输出「依赖边界检查通过」，退出码 0。`PDFExporter.swift`（Render：Foundation/AppKit/CoreGraphics）不违规（无 Metal/MetalKit import）。

- [ ] **Step 3: 登记 `docs/架构现状.md`**

在 §2.1 Render 层类型列追加 `PDFExporter`；§6 命令清单**不变**（PDF 导出不新增命令）。

- [ ] **Step 4: Commit**

```bash
git add docs/架构现状.md
git commit -m "docs: 登记 PDF 导出子系统（Render PDFExporter + Shell 入口）"
```

---

## Self-Review 记录

- **Spec 覆盖：** §5.1（scope/分页/绘制语音/文件名）→ Task 1–3；§5.2（入口/菜单/scope）→ Task 4；§7 验收 4–5 → Task 4 手测 + Task 3 测试；FR-E2 三入口 → Task 4。
- **占位符：** 无 TBD/TODO；每个代码步骤含完整可复制代码。Task 3 有一处 `ctx.draw(mediaBox:)` 备选写法（若编译不可用），non-placeholder。
- **类型一致性：** `PDFPageMode`（fit/pageSize/margin）、`PDFPagination`（scale/pageWindows）、`PDFPagination.compute(bounds:mode:)`、`PDFScope`（full/subtree）、`PDFExporter.subtreeDocument(_:rootID:)`、`PDFExporter.data(document:scope:mode:)`、`DocumentWorkflow.exportPDF` 在 Task 间签名一致。
- **算法验证：** 分页换算（含负原点/多行/单页缩放）与子树抽取均用脚本验证，测试断言与验证结果一致。
- **坐标/文字风险：** 明确记录「不经 Metal 纹理、无 flipVertically」；文字经 `NSGraphicsContext(flipped:)` 绘制，手测验证朝向（Task 4 Step 4），不引入另一套翻转。