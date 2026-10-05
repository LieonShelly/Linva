import Foundation
import Testing
@testable import LinvaApp

@Suite("ContentBlockRules")
struct ContentBlockRulesTests {
    private func textBlock(_ s: String) -> ContentBlock {
        ContentBlock(id: UUID(), kind: .text(s))
    }

    private func imageBlock(data: Data, pixelSize: ImagePixelSize) -> ContentBlock {
        ContentBlock(id: UUID(), kind: .image(.init(data: data, pixelSize: pixelSize)))
    }

    private func kinds(_ d: ContentBlockRules.CoalescingDecision) -> [ContentBlock.Kind] {
        switch d {
        case .noChange, .deleteNode: return []
        case .replaceBlocks(let new): return new.map(\.kind)
        }
    }

    private let px = ImagePixelSize(width: 10, height: 10)!

    /// M1-1：首块文 → 文上图下 [text, images]。
    @Test func firstBlockText_textBeforeImages() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文"), imageBlock(data: Data([0x01]), pixelSize: px)],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.text("新文"), .image(.init(data: Data([0x01]), pixelSize: px))])
    }

    /// M1-2：首块图 → 图上文下 [images, text]。
    @Test func firstBlockImage_imageBeforeText() {
        let d = ContentBlockRules.coalesce(
            original: [imageBlock(data: Data([0x01]), pixelSize: px), textBlock("原文")],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.image(.init(data: Data([0x01]), pixelSize: px)), .text("新文")])
    }

    /// M1-3：纯文本 → 退化为 [.text(newText)]。
    @Test func pureText_degradesToSingleTextBlock() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "纯文本新值", isRoot: true)
        #expect(kinds(d) == [.text("纯文本新值")])
    }

    /// M1-4：全图节点空草稿 → 内容未变（只剩图序列）→ .noChange（不补「未命名」）。
    @Test func allImageNode_emptyDraft_keepsOnlyImages() {
        let d = ContentBlockRules.coalesce(
            original: [imageBlock(data: Data([0x01]), pixelSize: px)], committedText: "", isRoot: true)
        #expect(d == .noChange)
    }

    /// M4：首个非空块判定——空文本块跳过：[.text(""), .image] → 首个非空是图 → 图上文下。
    @Test func emptyFirstTextBlock_isSkipped_imageWins() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock(""), imageBlock(data: Data([0x01]), pixelSize: px)],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.image(.init(data: Data([0x01]), pixelSize: px)), .text("新文")])
    }

    /// 删空：混合块（文本+图）→ 只留图（文本块被丢弃的 replaceBlocks 变换，非 noChange）。
    @Test func mixedBlocks_emptyDraft_keepsOnlyImages() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("新主题"), imageBlock(data: Data([0x01]), pixelSize: px)],
            committedText: "", isRoot: true)
        #expect(kinds(d) == [.image(.init(data: Data([0x01]), pixelSize: px))])
    }

    /// 删空：纯文本非根节点 → .deleteNode。
    @Test func pureTextNode_emptyDraft_deletesNode() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "", isRoot: false)
        #expect(d == .deleteNode)
    }

    /// 删空：纯文本根节点 → 补「未命名」（根不可删）。
    @Test func rootNode_emptyDraft_addsUnnamed() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "", isRoot: true)
        #expect(kinds(d) == [.text("未命名")])
    }

    /// no-op：内容不变 → .noChange（不入栈）。
    @Test func unchangedText_doesNotChange() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "原文", isRoot: true)
        #expect(d == .noChange)
    }
}
