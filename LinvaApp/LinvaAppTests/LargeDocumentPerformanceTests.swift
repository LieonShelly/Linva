import Foundation
import Testing
@testable import LinvaApp

/// 千节点级性能自测（App Store 过审 2.3 的量化护栏）。
/// 审核员会实测大文档流畅度；CPU 布局是全量重排的瓶颈候选，这里给出可重复的耗时基线。
@Suite("千节点性能自测")
struct LargeDocumentPerformanceTests {
    /// 生成 1000+ 节点树：root + 左右各 5 个一级分支 × 每分支 100 子节点。
    /// 全部展开（collapsed=false），模拟最坏全量布局路径。
    private func makeLargeDocument() -> MindMapDocument {
        func makeChild(_ i: Int, _ j: Int, side: Side) -> Node {
            Node(text: "分支\(i) 子节点\(j) 这是一个较长的节点文本来触发真实换行测量", side: side)
        }
        func makeBranch(_ i: Int, side: Side) -> Node {
            Node(text: "第\(i)个一级分支主题", side: side,
                 children: (0..<100).map { makeChild(i, $0, side: side) })
        }
        let left = (0..<5).map { makeBranch($0, side: .left) }
        let right = (0..<5).map { makeBranch($0, side: .right) }
        let root = Node(text: "根节点", children: left + right)
        var doc = MindMapDocument(version: MindMapDocument.currentVersion, root: root)
        doc.layout = .radial
        return doc
    }

    @Test func radialLayout_1000PlusNodes_completesQuickly() {
        let doc = makeLargeDocument()
        let pipeline = LayoutPipeline()
        let count = nodeCount(doc.root)

        // 预热（首跑含字体/度量缓存初始化）
        _ = pipeline.relayout(document: doc)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = pipeline.relayout(document: doc)
        }

        #expect(count > 1000, "测试构造节点数应超过 1000，实际 \(count)")
        #expect(elapsed < .milliseconds(2000),
                "1000+ 节点全量布局应 < 2s，实际 \(elapsed)")
        // 信息性输出（供人工对比回归）
        print("radial 布局节点数=\(count) 耗时=\(elapsed)")
    }

    @Test func logicLayout_1000PlusNodes_completesQuickly() {
        var doc = makeLargeDocument()
        doc.layout = .logic
        let pipeline = LayoutPipeline()
        let count = nodeCount(doc.root)

        _ = pipeline.relayout(document: doc)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = pipeline.relayout(document: doc)
        }

        #expect(count > 1000)
        #expect(elapsed < .milliseconds(2000),
                "1000+ 节点逻辑布局应 < 2s，实际 \(elapsed)")
        print("logic 布局节点数=\(count) 耗时=\(elapsed)")
    }

    private func nodeCount(_ node: Node) -> Int {
        1 + node.children.reduce(0) { $0 + nodeCount($1) }
    }
}
