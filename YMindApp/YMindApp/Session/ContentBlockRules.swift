import Foundation

/// 编辑提交时的内容块聚拢规则（SRP/OCP：新块类型加一个分支，不改 Session）。
enum ContentBlockRules {
    /// 提交决策：不改 / 整块替换 / 删除节点。
    enum CoalescingDecision: Equatable {
        case noChange
        case replaceBlocks([ContentBlock])
        case deleteNode
    }

    /// 对编辑提交做聚拢。语义与历史 DocumentSession.commitEditingIfNeeded 逐字节一致：
    /// 文本合并单块；图片按原相对顺序聚拢单侧（首个非空块是图 → 图上文下，否则文上图下）。
    /// 删空：有图只留图 / 纯文本非根删节点 / 根补「未命名」。
    /// no-op 按内容（忽略块 id）比较，内容不变 → .noChange 不入栈。
    static func coalesce(
        original: [ContentBlock],
        committedText: String,
        isRoot: Bool
    ) -> CoalescingDecision {
        let text = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = original.filter { block in
            if case .image = block.kind { return true } else { return false }
        }
        let firstBlockIsImage: Bool = {
            for block in original {
                switch block.kind {
                case .text(let s):
                    if !s.isEmpty { return false }   // 首个非空块是文本 → 文上图下
                case .image:
                    return true                      // 首个非空块是图片 → 图上文下
                }
            }
            return false   // 全空文本块 / 无块 → 文本在前默认
        }()
        var newBlocks: [ContentBlock]
        if text.isEmpty {
            if !images.isEmpty {
                newBlocks = images
            } else if !isRoot {
                return .deleteNode
            } else {
                newBlocks = [ContentBlock(id: UUID(), kind: .text("未命名"))]
            }
        } else if firstBlockIsImage {
            newBlocks = images + [ContentBlock(id: UUID(), kind: .text(text))]
        } else {
            newBlocks = [ContentBlock(id: UUID(), kind: .text(text))] + images
        }
        if newBlocks.map(\.kind) != original.map(\.kind) {
            return .replaceBlocks(newBlocks)
        }
        return .noChange
    }
}
