import Foundation
import Testing
@testable import LinvaApp

@Suite("DocumentPersistence")
struct DocumentPersistenceTests {
    private func tempURL(_ name: String) throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).linva")
    }

    /// round-trip：saveAs → 新 persistence load 回，内容一致、isDirty=false。
    @Test func saveAs_load_roundTrip() throws {
        let persistence = DocumentPersistence()
        let url = try tempURL("rt")
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "子")]
        try persistence.saveAs(document: doc, to: url)

        let loaded = DocumentPersistence()
        let read = try loaded.load(from: url)
        #expect(read.root.text == "根")
        #expect(read.root.children.count == 1)
        #expect(loaded.isDirty == false)
        #expect(loaded.fileURL == url)
    }

    /// save 无 fileURL → 抛 noFileURL。
    @Test func save_withoutFileURL_throws() {
        let persistence = DocumentPersistence()
        let doc = MindMapDocument.blank()
        #expect(throws: DocumentSessionError.noFileURL) {
            try persistence.save(document: doc)
        }
    }

    /// noteChange：文档变化 → true（脏），还原到 lastSaved → false（干净）。
    @Test func noteChange_tracksDirtyState() throws {
        let persistence = DocumentPersistence()
        let url = try tempURL("dirty")
        var doc = MindMapDocument.blank(rootText: "根")
        try persistence.saveAs(document: doc, to: url)

        doc.root.children = [Node(text: "x")]
        #expect(persistence.noteChange(current: doc) == true)

        doc.root.children = []
        #expect(persistence.noteChange(current: doc) == false)
    }

    /// adopt keepLastSaved=true：导入/恢复语义——lastSaved 保持旧值，撤销回载入态 isDirty 仍 true。
    @Test func adopt_keepLastSaved_preservesLastSaved() {
        let persistence = DocumentPersistence()
        let original = MindMapDocument.blank(rootText: "原始")
        persistence.adopt(document: original, fileURL: nil, isDirty: false,
                          keepLastSaved: false, regenerateID: true)

        var imported = MindMapDocument.blank(rootText: "导入")
        imported.root.children = [Node(text: "a")]
        persistence.adopt(document: imported, fileURL: nil, isDirty: true,
                          keepLastSaved: true, regenerateID: true)

        // lastSaved 仍是 original → 当前为 imported（载入态），撤销回载入态时 isDirty 仍 true
        #expect(persistence.noteChange(current: imported) == true)
    }

    /// restore 返回副本并保留 documentID；副本加载的 URL 恢复为 originalURL。
    @Test func restore_loadsDraft_returnsDocument() throws {
        let dir = try FileManager.default.url(for: .itemReplacementDirectory,
            in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let persistence = DocumentPersistence(autosaveStore: store)

        var draft = MindMapDocument.blank(rootText: "草稿根")
        draft.root.children = [Node(text: "恢复内容")]
        let meta = AutosaveMeta(documentID: UUID(), originalURL: nil,
                                savedAt: Date(), changeCount: 1, rootText: "草稿根")
        try store.write(document: draft, meta: meta)
        let offer = RecoveryOffer(meta: meta)

        let restored = try persistence.restore(draftFrom: offer)
        #expect(restored.root.text == "草稿根")
        #expect(restored.root.children[0].text == "恢复内容")
        #expect(persistence.isDirty == true)
    }
}
