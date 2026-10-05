import AppKit
import Testing
import Foundation
@testable import LinvaApp

@Suite("DocumentSession")
struct DocumentSessionTests {
    @Test func selectOnly_mirrorsSelectedIds() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let child = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(child)
        #expect(session.selectedIds == [child])
        #expect(session.selectionAnchorId == child)
        session.toggleInSelection(root)
        #expect(session.selectedIds == [child, root])
    }

    @Test func commandChanges_refreshUndoState_andReturnToCleanSnapshot() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        let initialRevision = session.undoRevision

        session.commandBus.execute(.addChild(parentId: rootId, text: "议题"))
        #expect(session.isDirty)
        #expect(session.commandBus.canUndo)
        #expect(session.undoRevision == initialRevision + 1)

        session.commandBus.undo()
        #expect(session.isDirty == false)
        #expect(session.commandBus.canRedo)
        #expect(session.undoRevision == initialRevision + 2)

        session.commandBus.redo()
        #expect(session.isDirty)
        #expect(session.model.document.root.children.count == 1)
        #expect(session.undoRevision == initialRevision + 3)
    }

    @Test func windowTitle_usesFilename_withoutManualDirtyMarker() throws {
        let session = DocumentSession()
        #expect(session.windowTitle == "未命名")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("标题-\(UUID().uuidString).linva")
        try session.saveAs(to: url)
        #expect(session.windowTitle == url.lastPathComponent)

        let root = session.model.document.root
        session.commandBus.execute(
            .setBlocks(
                id: root.id,
                old: root.blocks,
                new: [ContentBlock(id: UUID(), kind: .text("已修改"))]
            )
        )
        #expect(session.windowTitle == url.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func undoToLastSavedDocument_clearsDirtyState() throws {
        let session = DocumentSession()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-clean-\(UUID().uuidString).linva")
        try session.saveAs(to: url)

        let rootId = session.model.document.root.id
        session.commandBus.execute(.addChild(parentId: rootId, text: "临时议题"))
        #expect(session.isDirty)

        session.commandBus.undo()
        #expect(session.isDirty == false)

        session.commandBus.redo()
        #expect(session.isDirty)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func saveAndLoad_roundTrip() throws {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        session.commandBus.execute(.addChild(parentId: rootId, text: "议题"))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-test-\(UUID().uuidString).linva")
        try session.saveAs(to: url)
        #expect(session.isDirty == false)
        #expect(session.fileURL == url)

        let session2 = DocumentSession()
        try session2.load(from: url)
        #expect(session2.model.document.root.children.count == 1)
        #expect(session2.model.document.root.children[0].text == "议题")
        #expect(session2.isDirty == false)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func editingDraft_saveCommitsBeforeWriting() throws {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-edit-save-\(UUID().uuidString).linva")

        session.startEditing(rootId)
        session.draftText = "保存前草稿"
        try session.saveAs(to: url)

        let loaded = DocumentSession()
        try loaded.load(from: url)
        #expect(loaded.model.document.root.text == "保存前草稿")
        #expect(session.editingId == nil)
        #expect(session.isDirty == false)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func editingDraft_prepareReplaceCommitsAndBecomesDirty() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id

        session.startEditing(rootId)
        session.draftText = "替换前草稿"

        #expect(session.prepareReplace() == false)
        #expect(session.model.document.root.text == "替换前草稿")
        #expect(session.editingId == nil)
        #expect(session.isDirty)
    }

    @Test func editingDraft_failedLoadStillCommitsCurrentDocument() throws {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-edit-open-\(UUID().uuidString).linva")
        try Data("not-json".utf8).write(to: url)
        session.startEditing(rootId)
        session.draftText = "打开前草稿"

        #expect(throws: LinvaCodecError.decodingFailed) {
            try session.load(from: url)
        }
        #expect(session.model.document.root.text == "打开前草稿")
        #expect(session.isDirty)
        try? FileManager.default.removeItem(at: url)
    }

    /// P1-B：双击未改字提交 → 内容无变化 → no-op 不入栈、不脏（spec §2.1）。
    @Test func commitEditingIfNeeded_noChange_doesNotEnterUndoStack() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        session.startEditing(rootId)
        #expect(session.commandBus.canUndo == false)

        session.commitEditingIfNeeded()

        #expect(session.editingId == nil)
        #expect(session.commandBus.canUndo == false)   // 无变化不 setBlocks 入栈
        #expect(session.isDirty == false)
        #expect(session.model.document.root.text == "中心主题")
    }

    @Test func securityScopedAccess_startsBeforeOperation_andBalancesOwnedScopes() throws {
        let first = URL(fileURLWithPath: "/tmp/first.linva")
        let second = URL(fileURLWithPath: "/tmp/second.linva")
        var events: [String] = []

        var access: SecurityScopedAccess? = SecurityScopedAccess(
            startAccess: {
                events.append("start:\($0.lastPathComponent)")
                return true
            },
            stopAccess: { events.append("stop:\($0.lastPathComponent)") }
        )

        access?.replace(with: first) {
            events.append("io:first.linva")
        }
        access?.replace(with: second) {
            events.append("io:second.linva")
        }
        #expect(events == [
            "start:first.linva",
            "io:first.linva",
            "start:second.linva",
            "io:second.linva",
            "stop:first.linva",
        ])

        access = nil
        #expect(events.last == "stop:second.linva")
    }

    @Test func securityScopedAccess_failedStart_neverStops() throws {
        let url = URL(fileURLWithPath: "/tmp/no-scope.linva")
        var events: [String] = []
        let access = SecurityScopedAccess(
            startAccess: { _ in
                events.append("start")
                return false
            },
            stopAccess: { _ in events.append("stop") }
        )

        access.withAccess(to: url) {
            events.append("io")
        }

        #expect(events == ["start", "io"])
    }

    @MainActor
    @Test func terminateConfirmation_cancelReturnsTerminateCancel() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        let root = session.model.document.root
        session.commandBus.execute(.setBlocks(id: rootId, old: root.blocks, new: [ContentBlock(id: UUID(), kind: .text("未保存"))]))
        let delegate = AppDelegate()
        delegate.session = session
        delegate.confirmationHandler = { _ in false }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateCancel)
    }

    @Test func load_unsupportedVersion_leavesDocument() throws {
        let session = DocumentSession()
        let originalRoot = session.model.document.root.id
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-bad-\(UUID().uuidString).linva")
        try Data("{\"version\":9,\"root\":{\"id\":\"\(UUID())\",\"text\":\"x\",\"collapsed\":false,\"children\":[]}}".utf8)
            .write(to: url)
        #expect(throws: LinvaCodecError.self) {
            try session.load(from: url)
        }
        #expect(session.model.document.root.id == originalRoot)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func search_revealExpandsAncestors_andSelectsMatch() {
        let model = MindMapModel.makeNew()
        let session = DocumentSession(model: model)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "技术方案", side: .right, at: nil)
        let g = model.insertChild(parentId: a, text: "命中测试", side: nil, at: nil)
        model.setCollapsed(id: a, to: true)
        session.syncSelectionFromModel()

        session.runSearch(query: "命中")
        #expect(session.search.matches == [g])
        #expect(session.search.index == 0)

        session.revealSearchMatch(0)
        #expect(model.node(id: a)?.collapsed == false)   // 祖先展开
        #expect(session.selectedIds == [g])              // 选中收敛
    }

    @Test func search_noMatch_showsZeroAndNoJump() {
        let session = DocumentSession()
        session.runSearch(query: "不存在xyz")
        #expect(session.search.matches.isEmpty)
        #expect(session.search.index == -1)
        #expect(session.search.currentMatchId == nil)
    }

    @Test func openSearch_commitsEditingFirst() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "ABC", side: .right, at: nil)
        session.relayout()
        session.startEditing(a)
        session.draftText = "XYZ"
        session.openSearch()
        #expect(session.editingId == nil)                // 已提交
        #expect(session.model.node(id: a)?.text == "XYZ")
        #expect(session.search.isOpen)
    }

    @Test func centerCamera_movesToMatch() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.syncSelectionFromModel()
        session.relayout()
        let before = session.camera.scale
        session.centerCamera(on: a, viewport: CGSize(width: 400, height: 300))
        #expect(session.camera.scale == before)          // 保持缩放
        let frame = session.snapshot.frames[a]!.rect
        let c = session.camera.worldToScreen(CGPoint(x: frame.midX, y: frame.midY))
        #expect(abs(c.x - 200) < 0.001)
        #expect(abs(c.y - 150) < 0.001)
    }

    @Test func setLayout_switchesSnapshot_andGatesCanSetSide() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let child = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(child)
        #expect(session.canSetSide)

        session.setLayout(.logic)
        #expect(session.layout == .logic)
        #expect(session.model.document.layout == .logic)
        let rootFrame = session.snapshot.frames[root]!
        let childFrame = session.snapshot.frames[child]!
        #expect(childFrame.center.x > rootFrame.rect.maxX)
        #expect(!session.canSetSide)
        #expect(session.fitVersion == 1)

        session.commandBus.undo()
        #expect(session.layout == .radial)
        #expect(session.canSetSide)
        #expect(session.fitVersion == 2)
    }

    /// D8：brace 连线样式强制逻辑树 → 有效排布变化触发再适配；切回/撤消恢复。
    @Test func setEdgeStyle_braceRefits_whenEffectiveArrangementChanges() {
        let session = DocumentSession()
        #expect(session.edgeStyle == .elbow)
        let baseFit = session.fitVersion

        // elbow → brace：有效排布 radial → logic，触发再适配。
        session.setEdgeStyle(.brace)
        #expect(session.edgeStyle == .brace)
        #expect(session.fitVersion == baseFit + 1)

        // brace → elbow：有效排布 logic → radial，再次触发再适配。
        session.setEdgeStyle(.elbow)
        #expect(session.edgeStyle == .elbow)
        #expect(session.fitVersion == baseFit + 2)
    }

    /// 非 brace 样式族内部切换（elbow ↔ curve）不改变有效排布，不应触发再适配。
    @Test func setEdgeStyle_curveKeepsEffectiveArrangement_noRefit() {
        let session = DocumentSession()
        let baseFit = session.fitVersion
        session.setEdgeStyle(.curve)
        #expect(session.edgeStyle == .curve)
        #expect(session.fitVersion == baseFit)
    }
}

@Suite("DocumentSessionImport")
struct DocumentSessionImportTests {
    @Test func loadImported_adoptsDocument_asDirtyNewDoc_resetsUndo() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        session.commandBus.execute(.addChild(parentId: rootId, text: "已有内容"))
        let oldRevision = session.undoRevision

        var doc = MindMapDocument.blank(rootText: "导入根")
        doc.root.children = [Node(text: "子")]

        session.loadImported(doc)

        #expect(session.model.document.root.text == "导入根")
        #expect(session.model.document.root.children.count == 1)
        #expect(session.isDirty)                      // 新文档未保存 → dirty
        #expect(session.fileURL == nil)               // 非磁盘文件
        #expect(session.commandBus.canUndo == false)  // Undo 栈重置
        #expect(session.undoRevision == oldRevision + 1)
        #expect(session.importPreview == nil)         // 载入后清预览
    }

    @Test func cancelImport_discardsPreview_withoutLoading() {
        let session = DocumentSession()
        var doc = MindMapDocument.blank(rootText: "预览稿")
        doc.root.children = [Node(text: "x")]
        session.importPreview = ImportPreviewState(
            sourceName: "a.md", document: doc, nodeCount: 2, depth: 2
        )

        session.cancelImport()

        #expect(session.importPreview == nil)
        #expect(session.model.document.root.text == "中心主题")  // 未载入，保持原文档
        #expect(session.commandBus.canUndo == false)
    }

    @Test func loadImported_undoAll_keepsDirtyWithoutFile() {
        let session = DocumentSession()
        var doc = MindMapDocument.blank(rootText: "导入根")
        doc.root.children = [Node(text: "子")]
        session.loadImported(doc)

        session.commandBus.execute(.addChild(parentId: session.model.document.root.id, text: "新子"))
        while session.commandBus.canUndo {
            session.commandBus.undo()
        }

        // 导入文档无磁盘文件：撤销回载入态仍必须视为未保存，否则新建/打开/退出会静默丢弃。
        #expect(session.isDirty)
        #expect(session.fileURL == nil)
    }

    @Test func loadImported_resetsDocumentID() {
        let session = DocumentSession()
        let oldID = session.documentID
        var doc = MindMapDocument.blank(rootText: "新根")
        session.loadImported(doc)
        #expect(session.documentID != oldID)  // 每次载入新文档换新 docID（供自动保存配对）
    }
}

@Suite("DocumentSessionAutosave")
struct DocumentSessionAutosaveTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
    }

    @Test func save_clearsPendingCopy() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 注入同一 store：session 与断言侧指向同一目录
        let session = DocumentSession(autosaveStore: AutosaveStore(directory: dir))
        let autosave = AutosaveStore(directory: dir)

        // 模拟写了一份当前 documentID 的副本
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "x")]
        try autosave.write(document: doc, meta: AutosaveMeta(
            documentID: session.documentID, originalURL: nil,
            savedAt: Date(), changeCount: 1, rootText: "根"))

        // 触发保存（无 fileURL → saveAs）
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-as-\(UUID().uuidString).linva")
        try session.saveAs(to: url)

        // 保存后副本清除：latestPending 为 nil
        #expect(autosave.latestPending() == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func newDocument_resetsDocumentID_andClearsRecovery() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = DocumentSession(autosaveStore: AutosaveStore(directory: dir))
        let oldID = session.documentID
        session.recovery = RecoveryOffer(meta: AutosaveMeta(
            documentID: oldID, originalURL: nil,
            savedAt: Date(), changeCount: 1, rootText: "根"))
        #expect(session.recovery != nil)

        session.newDocument()

        #expect(session.documentID != oldID)  // 新文档换新 docID（供自动保存配对）
        #expect(session.recovery == nil)      // 清 recovery 态
    }

    @Test func loadImported_clearsRecovery() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = DocumentSession(autosaveStore: AutosaveStore(directory: dir))
        let oldID = session.documentID
        session.recovery = RecoveryOffer(meta: AutosaveMeta(
            documentID: oldID, originalURL: nil,
            savedAt: Date(), changeCount: 1, rootText: "根"))
        #expect(session.recovery != nil)

        var doc = MindMapDocument.blank(rootText: "导入根")
        doc.root.children = [Node(text: "子")]
        session.loadImported(doc)

        #expect(session.documentID != oldID)  // 导入换新 docID（供自动保存配对）
        #expect(session.recovery == nil)      // 清 recovery 态，避免 stale 横幅覆盖导入文档（final review F1）
    }
}

@Suite("DocumentSessionRecovery")
struct DocumentSessionRecoveryTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
    }

    @Test func scan_returnsOffer_whenPendingCopyExists() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = DocumentSession(autosaveStore: AutosaveStore(directory: dir))
        var doc = MindMapDocument.blank(rootText: "草稿根")
        doc.root.children = [Node(text: "a")]
        try AutosaveStore(directory: dir).write(
            document: doc,
            meta: AutosaveMeta(documentID: session.documentID, originalURL: nil,
                               savedAt: Date(), changeCount: 3, rootText: "草稿根"))

        let offer = session.scanForRecovery()
        #expect(offer != nil)
        #expect(offer?.meta.documentID == session.documentID)
    }

    @Test func restore_loadsDraft_asDirtyDocument() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let session = DocumentSession(autosaveStore: store)
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "恢复的内容")]
        let meta = AutosaveMeta(documentID: session.documentID, originalURL: nil,
                                savedAt: Date(), changeCount: 3, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        let offer = RecoveryOffer(meta: meta)
        try session.restore(draftFrom: offer)

        #expect(session.model.document.root.children.map(\.text) == ["恢复的内容"])
        #expect(session.isDirty)          // 恢复后标记未保存
        #expect(store.latestPending() == nil)  // 恢复后删该副本
    }

    @Test func discard_clearsAll_andKeepsLastSaved() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let session = DocumentSession(autosaveStore: store)
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "x")]
        let meta = AutosaveMeta(documentID: session.documentID, originalURL: nil,
                                savedAt: Date(), changeCount: 1, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        try session.discardDraft()

        #expect(store.latestPending() == nil)  // 忽略：清空副本
        #expect(session.isDirty == false)      // 回到最近正式保存版本（无 → 空文档 clean）
    }

    @Test func restore_undoAll_keepsDirtyTrue() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let session = DocumentSession(autosaveStore: store)
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "恢复的内容")]
        let meta = AutosaveMeta(documentID: session.documentID, originalURL: nil,
                                savedAt: Date(), changeCount: 3, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        try session.restore(draftFrom: RecoveryOffer(meta: meta))

        // 恢复后执行一条命令，再全部撤销回到恢复的载入态
        if let childID = session.model.document.root.children.first?.id {
            session.commandBus.execute(.addChild(parentId: childID, text: "新节点"))
        }
        while session.commandBus.canUndo {
            session.commandBus.undo()
        }

        // 恢复的草稿无磁盘文件：撤销回载入态仍必须保持 dirty，否则新建/打开/退出会静默丢弃。
        #expect(session.isDirty)
        #expect(session.fileURL == nil)
    }
}

@Suite("Session 图片")
struct SessionImageTests {
    private let px = ImagePixelSize(width: 64, height: 32)

    @Test func appendPastedImage_normalizesAndCommits() {
        let session = DocumentSession()
        session.imageNormalizer = { _ in (Data([0xAA]), ImagePixelSize(width: 8, height: 8)!) }
        let root = session.model.document.root.id

        #expect(session.appendPastedImage(from: Data([0x01])) == true)
        #expect(session.model.node(id: root)?.image == Data([0xAA]))
        #expect(session.isDirty)
    }

    @Test func appendPastedImage_withoutNormalizerOrSelection_fails() {
        let session = DocumentSession()
        #expect(session.appendPastedImage(from: Data([0x01])) == false)  // 无注入

        session.imageNormalizer = { _ in (Data([0xAA]), ImagePixelSize(width: 8, height: 8)!) }
        session.clearSelection()
        #expect(session.appendPastedImage(from: Data([0x01])) == false)  // 无选中
    }

    @Test func appendPastedImage_commitsEditingFirst() {
        let session = DocumentSession()
        session.imageNormalizer = { _ in (Data([0xAA]), px!) }
        let root = session.model.document.root.id
        session.startEditing(root)
        session.draftText = "先提交"
        _ = session.appendPastedImage(from: Data([0x01]))
        #expect(session.editingId == nil)
        #expect(session.model.node(id: root)?.text == "先提交")
    }

    /// 回归（Task 4）：编辑态 ⌘V 图片 —— CommitTextView.paste 拦截 → 壳层 paste 闭包
    /// （先 commitEditingIfNeeded 再 appendPastedImage，同序）。NSTextView 的 UI 行为
    /// 无法单测，逻辑链路（提交文字 → 追加图片块）由本用例钉死；真机手测见 Task 6。
    @Test func pasteImageWhileEditing_commitsTextThenAppendsBlock() {
        let session = DocumentSession()
        session.imageNormalizer = { _ in (Data([0xAA]), px!) }
        let root = session.model.document.root.id
        session.selectOnly(root)
        session.startEditing(root)
        session.draftText = "先提交的文字"
        // 模拟编辑态 ⌘V 图片：先 commitEditingIfNeeded 再 appendPastedImage（paste 闭包同序）。
        session.commitEditingIfNeeded()
        let ok = session.appendPastedImage(from: Data([0x01]))
        #expect(ok == true)
        #expect(session.editingId == nil)
        #expect(session.model.node(id: root)?.text == "先提交的文字")
        let blocks = session.model.node(id: root)?.blocks ?? []
        #expect(blocks.count == 2)
        if case .image(let img) = blocks[1].kind {
            #expect(img.data == Data([0xAA]))
        } else {
            Issue.record("blocks[1] 应为图片块")
        }
    }

    @Test func appendPastedImage_appendsBlockAtEnd() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        let normalizer: (Data) -> (data: Data, pixelSize: ImagePixelSize)? = {
            ($0, px)
        }
        session.imageNormalizer = normalizer
        session.selectOnly(root)
        let ok = session.appendPastedImage(from: Data([0x01]))
        #expect(ok == true)
        #expect(session.model.node(id: root)?.blocks.count == 2)
        if case .image(let img) = session.model.node(id: root)!.blocks[1].kind {
            #expect(img.data == Data([0x01]))
        } else {
            Issue.record("blocks[1] 应为图片")
        }
    }

    /// P1-C：选中图片块后 ⌘V/拖入 → 替换该块（块 id 不变、块数不变），而非追加末尾。
    @Test func appendPastedImage_replacesSelectedImageBlock() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let px = ImagePixelSize(width: 10, height: 10)!
        let blockId = session.model.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px)
        session.imageNormalizer = { _ in (Data([0xBB]), px) }
        session.selectImageBlock(nodeId: root, blockId: blockId)

        let ok = session.appendPastedImage(from: Data([0x02]))

        #expect(ok == true)
        let blocks = session.model.node(id: root)?.blocks ?? []
        #expect(blocks.count == 2)               // 替换非追加：块数不变
        #expect(blocks[1].id == blockId)         // 块 id 不变
        if case .image(let img) = blocks[1].kind {
            #expect(img.data == Data([0xBB]))    // 数据被替换
        } else {
            Issue.record("blocks[1] 应为图片块")
        }
        #expect(session.selectedImageBlock == nil)  // 替换后回落，与删块一致
    }

    /// 回归（Important #2，spec §5.2）：selectImageBlock 后 selectOnly(nil)（点空白）→ 清图片选中。
    @Test func selectImageBlock_thenSelectOnlyNil_clearsSelection() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let blockId = session.model.appendImageBlock(
            id: root, image: Data([0x01]), pixelSize: ImagePixelSize(width: 10, height: 10)!
        )
        session.selectImageBlock(nodeId: root, blockId: blockId)
        #expect(session.selectedImageBlock != nil)

        session.selectOnly(nil)
        #expect(session.selectedImageBlock == nil)
        #expect(session.selectedIds.isEmpty)
    }

    /// 回归（Important #2，spec §5.2）：selectImageBlock 后选中其它节点 → 亦清图片选中。
    @Test func selectImageBlock_thenSelectOtherNode_clearsSelection() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = session.model.insertChild(parentId: root, text: "B", side: .right, at: nil)
        let blockId = session.model.appendImageBlock(
            id: a, image: Data([0x01]), pixelSize: ImagePixelSize(width: 10, height: 10)!
        )
        session.selectImageBlock(nodeId: a, blockId: blockId)
        #expect(session.selectedImageBlock != nil)

        session.selectOnly(b)
        #expect(session.selectedImageBlock == nil)
        #expect(session.selectedIds == [b])
    }

    /// 回归（Important #2，spec §5.2）：selectImageBlock 后 replaceSelection（⌘A / 框选路径）→ 亦清图片选中。
    @Test func selectImageBlock_thenReplaceSelection_clearsSelection() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let blockId = session.model.appendImageBlock(
            id: root, image: Data([0x01]), pixelSize: ImagePixelSize(width: 10, height: 10)!
        )
        session.selectImageBlock(nodeId: root, blockId: blockId)
        #expect(session.selectedImageBlock != nil)

        session.replaceSelection([root], anchorId: root)
        #expect(session.selectedImageBlock == nil)
        #expect(session.selectedIds == [root])
    }

    /// ⌫ 分派：删除选中的图片块并回落选中；无图片选中则 no-op。
    @Test func removeSelectedImageBlock_deletesBlockAndClearsSelection() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let blockId = session.model.appendImageBlock(
            id: root,
            image: Data([0x01]),
            pixelSize: ImagePixelSize(width: 10, height: 10)!
        )
        session.selectImageBlock(nodeId: root, blockId: blockId)
        #expect(session.selectedImageBlock != nil)

        session.removeSelectedImageBlock()
        #expect(session.model.node(id: root)?.blocks.count == 1)
        #expect(session.selectedImageBlock == nil)
    }

    /// 选中/清选是会话态：不入 Undo 栈；删除块本身才入栈。
    @Test func selectImageBlock_clearOnEscapeProxy_andNotInUndoStack() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let blockId = session.model.appendImageBlock(
            id: root, image: Data([0x01]), pixelSize: ImagePixelSize(width: 10, height: 10)!
        )
        session.selectImageBlock(nodeId: root, blockId: blockId)
        #expect(session.selectedImageBlock?.blockId == blockId)
        session.clearImageSelection()
        #expect(session.selectedImageBlock == nil)
        #expect(session.commandBus.canUndo == false)
    }
}

