import Testing
import Foundation
@testable import YMindApp

@Suite("AutosaveStore")
struct AutosaveStoreTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
    }

    @Test func write_createsDocAndMetaFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "子")]
        let meta = AutosaveMeta(documentID: UUID(), originalURL: nil, savedAt: Date(),
                                changeCount: 3, rootText: "根")
        try store.write(document: doc, meta: meta)

        // 两个文件存在
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 2)          // .ymind + .meta.json
        let ymind = files.first { $0.hasSuffix(".ymind") }
        let metaF = files.first { $0.hasSuffix(".meta.json") }
        #expect(ymind != nil && metaF != nil)
    }

    @Test func load_roundTripsDocument() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "a"), Node(text: "b")]
        let meta = AutosaveMeta(documentID: docID, originalURL: nil, savedAt: Date(),
                                changeCount: 1, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        let loaded = try store.load(documentID: docID)
        #expect(loaded.root.text == "草稿")
        #expect(loaded.root.children.map(\.text) == ["a", "b"])
    }

    @Test func latestPending_returnsNewestBySavedAt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let oldID = UUID(); let newID = UUID()
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: oldID, originalURL: nil,
            savedAt: Date(timeIntervalSince1970: 1000), changeCount: 1, rootText: "旧"))
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: newID, originalURL: nil,
            savedAt: Date(timeIntervalSince1970: 2000), changeCount: 2, rootText: "新"))

        let latest = store.latestPending()
        #expect(latest?.documentID == newID)
    }

    @Test func delete_removesPair() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: docID, originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "根"))

        try store.delete(documentID: docID)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }

    @Test func clearAll_removesEverything() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: UUID(), originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "r1"))
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: UUID(), originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "r2"))

        try store.clearAll()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }

    @Test func metadata_encodesAndDecodes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        let url = "file:///tmp/x.ymind"
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: docID, originalURL: url, savedAt: Date(timeIntervalSince1970: 42),
            changeCount: 7, rootText: "根"))

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let metaFile = files.first { $0.hasSuffix(".meta.json") }!
        let data = try Data(contentsOf: dir.appendingPathComponent(metaFile))
        let decoded = try JSONDecoder().decode(AutosaveMeta.self, from: data)
        #expect(decoded.documentID == docID)
        #expect(decoded.originalURL == url)
        #expect(decoded.changeCount == 7)
    }
}