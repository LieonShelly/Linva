import Foundation

enum LinvaCodecError: Error, Equatable {
    case unsupportedVersion(Int)
    case decodingFailed
}

enum LinvaCodec {
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
            throw LinvaCodecError.decodingFailed
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
        // 迁移：v4 → v5（layout 缺省 .radial；MindMapDocument 解码器对缺失 layout 天然容错）。
        if doc.version == 4 {
            doc.version = 5
        }
        // 迁移：v5 → v6（根折叠由单值 collapsed 改为左右侧独立 collapsedLeft/collapsedRight）。
        // v5 根 collapsed=true 语义 = 左右都折；折叠根后迁为两侧独立 true，清空遗留 collapsed。
        if doc.version == 5 {
            if doc.root.collapsed {
                doc.root.collapsedLeft = true
                doc.root.collapsedRight = true
            }
            doc.root.collapsed = false
            doc.version = 6
        }
        // 迁移：v6 → v7（edgeStyle 缺省 .elbow；MindMapDocument 解码器对缺失字段天然容错）。
        if doc.version == 6 {
            doc.version = 7
        }
        guard doc.version == MindMapDocument.currentVersion else {
            throw LinvaCodecError.unsupportedVersion(doc.version)
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
        // v6：根折叠态只由 collapsedLeft/collapsedRight 承载；遗留单值 collapsed 恒为 false。
        root.collapsed = false
        root.children = root.children.map { child in
            var c = child
            c.collapsedLeft = false
            c.collapsedRight = false
            c.children = stripSide(c.children, warnings: &warnings)
            return c
        }
        // layout/edgeStyle 是文档属性：sanitize 重建时须保留，否则逻辑图/曲线文档消毒后被重置。
        return MindMapDocument(version: document.version, root: root, layout: document.layout, edgeStyle: document.edgeStyle)
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
            // v6：左右侧折叠态仅根有效；非根强制 false（与 side 同层级约束）。
            x.collapsedLeft = false
            x.collapsedRight = false
            x.children = stripSide(x.children, warnings: &warnings)
            return x
        }
    }
}
