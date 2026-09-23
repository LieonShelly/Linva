import Testing
import Foundation
@testable import YMindApp

@Suite("DocumentSession")
struct DocumentSessionTests {
    @Test func commandChanges_markDocumentDirty_andSupportUndoRedo() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id

        session.commandBus.execute(.addChild(parentId: rootId, text: "议题"))
        #expect(session.isDirty)
        #expect(session.commandBus.canUndo)

        session.commandBus.undo()
        #expect(session.isDirty)
        #expect(session.commandBus.canRedo)

        session.commandBus.redo()
        #expect(session.isDirty)
        #expect(session.model.document.root.children.count == 1)
    }

    @Test func windowTitle_reflectsFilenameAndDirtyState() throws {
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
        #expect(session.windowTitle == "\(url.lastPathComponent) •")
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
