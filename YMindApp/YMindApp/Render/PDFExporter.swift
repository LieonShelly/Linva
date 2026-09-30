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
/// 分页纯函数入口：把内容包围盒换算成「每页该画哪个世界窗口 + 统一缩放」。
struct PDFPagination: Equatable {
    var scale: CGFloat = 1
    var pageWindows: [CGRect] = []

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
        let mediaBox = CGRect(x: 0, y: 0, width: mode.pageSize.width, height: mode.pageSize.height)
        var mb = mediaBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mb, nil) else {
            return nil
        }
        // PDF 每页

        let appearance = NSAppearance(named: .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            for window in pagination.pageWindows {
                ctx.beginPDFPage(nil)
                // 纸色背景（ctx.draw(mediaBox:) 在当前 SDK 编译期不可用，用显式填充兜底）
                ctx.saveGState()
                ctx.setFillColor(cgColor(PNGExporter.paperColor))
                ctx.fill(mediaBox)
                ctx.restoreGState()
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