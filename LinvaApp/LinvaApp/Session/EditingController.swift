import Foundation

/// 编辑会话控制器（SRP：编辑草稿态的基线记录 + 提交/取消编排）。
/// 对外 draftText 仍由 DocumentSession 持有（CommitTextView 双向绑定），本对象只持内部基线。
final class EditingController {
    private let model: MindMapModel
    private let commandBus: CommandBus

    private(set) var editingId: UUID?
    private(set) var originalBlocks: [ContentBlock] = []
    private(set) var originalEditingText = ""

    init(model: MindMapModel, commandBus: CommandBus) {
        self.model = model
        self.commandBus = commandBus
    }

    /// 开始编辑。节点须存在且已布局（有 frame）；若正编辑另一节点，先提交旧节点。
    /// - Parameters:
    ///   - id: 目标节点
    ///   - currentDraft: DocumentSession 当前草稿（切换节点时用于提交旧节点）
    ///   - snapshotFrames: 当前布局帧表（无 frame 的节点静默不启动编辑）
    /// - Returns: 是否开始编辑
    func begin(id: UUID, currentDraft: String, snapshotFrames: [UUID: NodeFrame]) -> Bool {
        guard model.node(id: id) != nil, snapshotFrames[id] != nil else { return false }
        if editingId != nil, editingId != id {
            _ = commit(draftText: currentDraft)
        }
        guard let node = model.node(id: id) else { return false }
        editingId = id
        originalEditingText = node.text
        originalBlocks = node.blocks
        return true
    }

    /// 提交编辑：聚拢 → 落命令栈。返回是否有进行中的编辑（无论是否入栈）。
    @discardableResult
    func commit(draftText: String) -> Bool {
        guard let editingId else { return false }
        let isRoot = editingId == model.document.root.id
        let decision = ContentBlockRules.coalesce(
            original: originalBlocks,
            committedText: draftText,
            isRoot: isRoot
        )
        switch decision {
        case .noChange:
            break
        case .replaceBlocks(let new):
            commandBus.execute(.setBlocks(id: editingId, old: originalBlocks, new: new))
        case .deleteNode:
            commandBus.execute(.delete(ids: [editingId]))
        }
        self.editingId = nil
        originalBlocks = []
        originalEditingText = ""
        return true
    }

    /// 取消编辑：丢弃草稿改动，仅清基线。
    func cancel() {
        editingId = nil
        originalBlocks = []
        originalEditingText = ""
    }
}
