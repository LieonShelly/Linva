// YMindAppTests/MetalRendererTests.swift
import AppKit
import CoreGraphics
import Foundation
import Metal
import Testing
@testable import YMindApp

@Suite("MetalRenderer 连接器渲染")
struct MetalRendererTests {
    @Test func connectorVertices_strokesPathAndDrawsMarkerCircle() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil)
        let renderer = try MetalRenderer(device: MTLCreateSystemDefaultDevice()!)

        let id = UUID()
        let snapshot = LayoutSnapshot(
            frames: [:],
            connectors: [
                ConnectorGeometry(
                    id: id,
                    path: [.zero, CGPoint(x: 100, y: 0)],
                    marker: ConnectorMarker(kind: .circle, center: CGPoint(x: 50, y: 50), radius: 8)
                )
            ]
        )
        // 路径 1 段 = 1 个 segmentQuad = 6 顶点；圆圈 16 段三角扇 = 48 顶点。
        let visible = renderer.connectorVertices(
            snapshot: snapshot,
            visibleIds: Set([id]),
            camera: Camera()
        )
        #expect(visible.count == 6 + 48)
        // 不可见 id → 整条连接器（含 marker）不产出顶点。
        let hidden = renderer.connectorVertices(
            snapshot: snapshot,
            visibleIds: Set(),
            camera: Camera()
        )
        #expect(hidden.isEmpty)
    }

    /// 像素级冒烟：真实 brace 根括号（BraceProvider.buildBrace, isMain+hasCircle）
    /// 的嘴口圆圈必须真的画进离屏渲染（renderImage = PNG 导出同一路径）。
    @Test func renderImage_drawsBraceMouthMarkerCircle() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil)
        let renderer = try MetalRenderer(device: MTLCreateSystemDefaultDevice()!)

        let rootId = UUID()
        let childA = UUID()
        let childB = UUID()
        let rootFrame = NodeFrame(
            id: rootId, text: "根", center: .zero,
            size: NodeSize(width: 100, height: 40),
            isRoot: true, side: nil, collapsed: false, hiddenCount: 0
        )
        let childAFrame = NodeFrame(
            id: childA, text: "A", center: CGPoint(x: 150, y: -40),
            size: NodeSize(width: 40, height: 20),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0
        )
        let childBFrame = NodeFrame(
            id: childB, text: "B", center: CGPoint(x: 150, y: 40),
            size: NodeSize(width: 40, height: 20),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0
        )
        let brace = BraceProvider.buildBrace(
            id: rootId, parent: rootFrame, first: childAFrame, last: childBFrame,
            childCount: 2, isMain: true, hasCircle: true
        )
        let marker = try #require(brace.marker)

        let frames: [UUID: NodeFrame] = [rootId: rootFrame, childA: childAFrame, childB: childBFrame]
        let bounds = frames.values.reduce(CGRect.null) { $0.union($1.rect) }
        let withMarker = LayoutSnapshot(frames: frames, connectors: [brace])
        let withoutMarker = LayoutSnapshot(
            frames: frames,
            connectors: [ConnectorGeometry(id: brace.id, path: brace.path, marker: nil)]
        )

        let paper = NSColor.white
        let imageWith = try #require(renderer.renderImage(
            snapshot: withMarker, contentBounds: bounds, paper: paper
        ))
        let imageWithout = try #require(renderer.renderImage(
            snapshot: withoutMarker, contentBounds: bounds, paper: paper
        ))
        let repWith = try #require(NSBitmapImageRep(cgImage: imageWith))
        let repWithout = try #require(NSBitmapImageRep(cgImage: imageWithout))

        // 采样点：圆圈上缘内侧（marker.center 上方 3pt）——圆圈内、路径描边外
        // （mouth 段只在 yMid 水平线 ±1.5pt 内，圆圈半径 4.5）。
        let probe = CGPoint(x: marker.center.x, y: marker.center.y - 3)
        let scale = min(max(2400 / max(bounds.width, bounds.height), 0.35), 2)
        let px = Int((probe.x - bounds.minX + 48) * scale)
        let py = Int((probe.y - bounds.minY + 48) * scale)

        func differsFromPaper(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y) else { return true }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            // separatorColor(aqua) ≈ 黑 α0.098 → 白纸混合后 ≈ (230,230,230)，容差 3%。
            return abs(r - 1) > 0.03 || abs(g - 1) > 0.03 || abs(b - 1) > 0.03
        }
        // 有 marker：圆圈上缘内侧非纯纸面（描边色已画入）。
        #expect(differsFromPaper(repWith, x: px, y: py))
        // 无 marker：同一采样点为纯纸面（圆圈确实来自 marker，而非路径/节点）。
        #expect(!differsFromPaper(repWithout, x: px, y: py))
    }
}
