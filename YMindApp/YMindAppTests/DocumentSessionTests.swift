import AppKit
import Testing
import Foundation
@testable import YMindApp

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
            .appendingPathComponent("标题-\(UUID().uuidString).ymind")
        try session.saveAs(to: url)
        #expect(session.windowTitle == url.lastPathComponent)

        session.commandBus.execute(
            .setText(
                id: session.model.document.root.id,
                old: session.model.document.root.text,
                new: "已修改"
            )
        )
        #expect(session.windowTitle == url.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func undoToLastSavedDocument_clearsDirtyState() throws {
        let session = DocumentSession()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymind-clean-\(UUID().uuidString).ymind")
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
            .appendingPathComponent("ymind-test-\(UUID().uuidString).ymind")
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
            .appendingPathComponent("ymind-edit-save-\(UUID().uuidString).ymind")

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
            .appendingPathComponent("ymind-edit-open-\(UUID().uuidString).ymind")
        try Data("not-json".utf8).write(to: url)
        session.startEditing(rootId)
        session.draftText = "打开前草稿"

        #expect(throws: YMindCodecError.decodingFailed) {
            try session.load(from: url)
        }
        #expect(session.model.document.root.text == "打开前草稿")
        #expect(session.isDirty)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func securityScopedAccess_startsBeforeOperation_andBalancesOwnedScopes() throws {
        let first = URL(fileURLWithPath: "/tmp/first.ymind")
        let second = URL(fileURLWithPath: "/tmp/second.ymind")
        var events: [String] = []

        var access: SecurityScopedAccess? = SecurityScopedAccess(
            startAccess: {
                events.append("start:\($0.lastPathComponent)")
                return true
            },
            stopAccess: { events.append("stop:\($0.lastPathComponent)") }
        )

        access?.replace(with: first) {
            events.append("io:first.ymind")
        }
        access?.replace(with: second) {
            events.append("io:second.ymind")
        }
        #expect(events == [
            "start:first.ymind",
            "io:first.ymind",
            "start:second.ymind",
            "io:second.ymind",
            "stop:first.ymind",
        ])

        access = nil
        #expect(events.last == "stop:second.ymind")
    }

    @Test func securityScopedAccess_failedStart_neverStops() throws {
        let url = URL(fileURLWithPath: "/tmp/no-scope.ymind")
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
        session.commandBus.execute(.setText(id: rootId, old: "中心主题", new: "未保存"))
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
            .appendingPathComponent("ymind-bad-\(UUID().uuidString).ymind")
        try Data("{\"version\":9,\"root\":{\"id\":\"\(UUID())\",\"text\":\"x\",\"collapsed\":false,\"children\":[]}}".utf8)
            .write(to: url)
        #expect(throws: YMindCodecError.self) {
            try session.load(from: url)
        }
        #expect(session.model.document.root.id == originalRoot)
        try? FileManager.default.removeItem(at: url)
    }
}
