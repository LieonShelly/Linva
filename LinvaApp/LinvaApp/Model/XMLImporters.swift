import Foundation

/// 解析期间的临时可变节点（Node 为值类型，class 便于增量构建），结束时整体转成 Node。
private final class XMLNodeBuilder {
    var text: String
    var children: [XMLNodeBuilder] = []

    init(text: String) { self.text = text }

    func makeNode() -> Node {
        Node(text: text, children: children.map { $0.makeNode() })
    }
}

/// 共用 XMLParser 把嵌套节点结构解析为树。
final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    enum NodeKind { case opml, freeMind }
    private let kind: NodeKind
    private var stack: [XMLNodeBuilder] = []
    private(set) var root: MindMapDocument?

    init(kind: NodeKind) { self.kind = kind; super.init() }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let isNodeElement = elementName == (kind == .opml ? "outline" : "node")
        guard isNodeElement else { return }

        let raw = kind == .opml ? attributeDict["text"] : attributeDict["TEXT"]
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespaces)
        let node = XMLNodeBuilder(text: trimmed.isEmpty ? "未命名" : trimmed)

        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let isNodeElement = elementName == (kind == .opml ? "outline" : "node")
        // 根节点的结束标签不去栈：parse 结束后 stack.first 即文档根。
        if isNodeElement, stack.count > 1 {
            stack.removeLast()
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard let builderRoot = stack.first else { return }
        var root = builderRoot.makeNode()
        for (index, _) in root.children.enumerated() {
            root.children[index].side = (index % 2 == 0) ? .left : .right
        }
        self.root = MindMapDocument(version: MindMapDocument.currentVersion, root: root)
    }
}

struct OPMLImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        try XMLTreeBuilder.build(data, kind: .opml)
    }
}

struct FreeMindImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        try XMLTreeBuilder.build(data, kind: .freeMind)
    }
}

extension XMLTreeBuilder {
    static func build(_ data: Data, kind: NodeKind) throws -> MindMapDocument {
        let builder = XMLTreeBuilder(kind: kind)
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw ImportError.invalidXML
        }
        return root
    }
}