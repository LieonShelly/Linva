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