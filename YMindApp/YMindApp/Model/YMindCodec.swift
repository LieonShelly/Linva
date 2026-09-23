import Foundation

enum YMindCodecError: Error, Equatable {
    case unsupportedVersion(Int)
    case decodingFailed
}

enum YMindCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    static func encode(_ document: MindMapDocument) throws -> Data {
        try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> MindMapDocument {
        let doc: MindMapDocument
        do {
            doc = try decoder.decode(MindMapDocument.self, from: data)
        } catch {
            throw YMindCodecError.decodingFailed
        }
        guard doc.version == MindMapDocument.currentVersion else {
            throw YMindCodecError.unsupportedVersion(doc.version)
        }
        return sanitize(doc)
    }

    private static func sanitize(_ document: MindMapDocument) -> MindMapDocument {
        var root = document.root
        root.side = nil
        root.children = root.children.map { child in
            var c = child
            c.children = stripSide(c.children)
            return c
        }
        return MindMapDocument(version: document.version, root: root)
    }

    private static func stripSide(_ nodes: [Node]) -> [Node] {
        nodes.map { n in
            var x = n
            x.side = nil
            x.children = stripSide(x.children)
            return x
        }
    }
}
