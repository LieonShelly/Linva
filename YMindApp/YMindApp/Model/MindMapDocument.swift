import Foundation

/// 文档布局类型：同一棵树的画布排布方式（随 `.ymind` 持久化，v5）。
enum LayoutKind: String, Codable, Sendable, Equatable, Hashable {
    /// 中心辐射：根在中心、左右对称展开（v1 起默认）。
    case radial
    /// 逻辑图（总分树）：根在最左、层级向右层层展开。
    case logic
}

/// 连线样式：同父节点的分支连线绘制方式（随 `.ymind` 持久化，v7）。
enum EdgeStyle: String, Codable, CaseIterable, Sendable, Hashable {
    /// 折线（肘形），默认。
    case elbow
    /// 平滑曲线。
    case curve
    /// 大括号（树形括号）。
    case brace
}

struct MindMapDocument: Equatable, Codable, Sendable {
    static let currentVersion = 7
    var version: Int
    var root: Node
    /// 布局（文档属性，v5 起持久化；v4 及以下缺省 .radial，零拒绝迁移）。
    var layout: LayoutKind = .radial
    /// 连线样式（文档属性，v7 起持久化；v6 及以下缺省 .elbow，零拒绝迁移）。
    var edgeStyle: EdgeStyle = .elbow

    init(version: Int, root: Node, layout: LayoutKind = .radial, edgeStyle: EdgeStyle = .elbow) {
        self.version = version
        self.root = root
        self.layout = layout
        self.edgeStyle = edgeStyle
    }

    static func blank(rootText: String = "中心主题") -> MindMapDocument {
        MindMapDocument(version: currentVersion, root: Node(text: rootText))
    }

    private enum CodingKeys: String, CodingKey {
        case version, root, layout, edgeStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        root = try c.decode(Node.self, forKey: .root)
        // v4 及以下无 layout 字段 → 缺省 .radial（同 fill/image/blocks 缺省容错模式）。
        layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? .radial
        // v6 及以下无 edgeStyle 字段 → 缺省 .elbow（同 layout 缺省容错模式）。
        edgeStyle = try c.decodeIfPresent(EdgeStyle.self, forKey: .edgeStyle) ?? .elbow
    }
}
