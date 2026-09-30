// Render/PDFExporter.swift
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