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
        var doc: MindMapDocument
        do {
            doc = try decoder.decode(MindMapDocument.self, from: data)
        } catch {
            throw YMindCodecError.decodingFailed
        }
        // 迁移：v1 → v2（fill 缺省 nil，仅版本号升迁；Node 解码器对缺失 fill 天然容错）。
        if doc.version == 1 {
            doc.version = 2
        }
        // 迁移：v2 → v3（image/imagePixelSize 缺省 nil，仅版本号升迁）。
        if doc.version == 2 {
            doc.version = 3
        }
        // 迁移：v3 → v4（blocks 由 Node 解码器 fallback 合成，此处仅抬版本号）。
        if doc.version == 3 {
            doc.version = 4
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
