import Testing
import Foundation
@testable import YMindApp

@Suite("DocumentSession")
struct DocumentSessionTests {
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

    @Test func securityScopedAccess_releasesScope_whenReplacingAndDeinitializing() {
        let first = URL(fileURLWithPath: "/tmp/first.ymind")
        let second = URL(fileURLWithPath: "/tmp/second.ymind")
        var started: [URL] = []
        var stopped: [URL] = []

        var access: SecurityScopedAccess? = SecurityScopedAccess(
            startAccess: {
                started.append($0)
                return true
            },
            stopAccess: { stopped.append($0) }
        )

        access?.replace(with: first, accessAlreadyStarted: true)
        #expect(started.isEmpty)
        access?.replace(with: second, accessAlreadyStarted: false)
        #expect(started == [second])
        #expect(stopped == [first])

        access = nil
        #expect(stopped == [first, second])
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
