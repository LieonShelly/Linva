import Foundation
import Testing
@testable import YMindApp

/// 用于验证 LayoutPipeline 换引擎的假实现。
struct FakeLayoutEngine: LayoutEngine {
    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot {
        LayoutSnapshot(frames: [:], edges: [])
    }
}

@Suite("LayoutPipeline")
struct LayoutPipelineTests {
    /// 默认引擎 = RadialLayout：产出与直接调用 RadialLayout.layout 的帧数一致。
    @Test func defaultUsesRadialLayout() {
        let pipeline = LayoutPipeline()
        let doc = MindMapDocument.blank()
        let snap = pipeline.relayout(document: doc)
        let expected = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames.count == expected.frames.count)
    }

    /// 注入假引擎 → 换布局不碰 Session。
    @Test func injectedEngine_isUsed() {
        let pipeline = LayoutPipeline(layoutEngineType: FakeLayoutEngine.self)
        let snap = pipeline.relayout(document: MindMapDocument.blank())
        #expect(snap.frames.isEmpty)
    }
}
