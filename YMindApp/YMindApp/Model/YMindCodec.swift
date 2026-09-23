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
        try encoder.encode(sanitize(document))
    }

    static func decode(_ data: Data) throws -> MindMapDocument {
        var warnings: [String]? = nil
        return try decode(data, warnings: &warnings)
    }

    static func decode(_ data: Data, warnings: inout [String]?) throws -> MindMapDocument {
        let doc: MindMapDocument
        do {
            doc = try decoder.decode(MindMapDocument.self, from: data)
        } catch {
            throw YMindCodecError.decodingFailed
        }
        guard doc.version == MindMapDocument.currentVersion else {
            throw YMindCodecError.unsupportedVersion(doc.version)
        }
        return sanitize(doc, warnings: &warnings)
    }

    private static func sanitize(_ document: MindMapDocument) -> MindMapDocument {
        var warnings: [String]? = nil
        return sanitize(document, warnings: &warnings)
    }

    private static func sanitize(_ document: MindMapDocument, warnings: inout [String]?) -> MindMapDocument {
        var root = document.root
        root.side = nil
        root.children = root.children.map { child in
            var c = child
            c.children = stripSide(c.children, warnings: &warnings)
            return c
        }
        return MindMapDocument(version: document.version, root: root)
    }

    private static func stripSide(_ nodes: [Node], warnings: inout [String]?) -> [Node] {
        nodes.map { n in
            var x = n
            if x.side != nil {
                warnings?.append(
                    "深层节点的 side 字段已被忽略（节点 id: \(x.id.uuidString)）"
                )
                x.side = nil
            }
            x.children = stripSide(x.children, warnings: &warnings)
            return x
        }
    }
}
