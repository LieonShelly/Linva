import AppKit
import CoreGraphics
import Foundation
import MetalKit

/// 全展开整图 PNG 导出（FR-E3）。
/// 流程：复制并展开副本 → 布局 → 按包围盒离屏光栅化；原文档不动、不入 Undo（FR-E4）。
enum PNGExporter {
    /// 生成 PNG 数据；失败返回 nil。
    /// `maxPixelBudget` = 导出总像素预算（内容越大包围盒越大 → 图越大，直到预算上限；
    /// 取代旧的固定长边 2400 硬降采样——后者让上千节点的大树模糊）。
    static func data(
        document: MindMapDocument,
        maxPixelBudget: Int = 100_000_000,
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
                maxPixelBudget: maxPixelBudget,
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
