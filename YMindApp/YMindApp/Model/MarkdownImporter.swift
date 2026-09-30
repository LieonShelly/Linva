import Foundation

/// 把 Markdown 大纲解析为 MindMapDocument（与 MarkdownExporter 对称：导出标题→树，导入树←标题）。
/// 纯函数、仅 Foundation。
struct MarkdownImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline)

        var headingCount = 0
        var root: Node?
        // levels[k] = 深度 k 的最近标题节点的索引路径（1-based）；按需裁剪更深层级。
        // 用索引路径而非节点引用，因为 Node 是值类型（无整树拷贝，仅重写根到追加点 spine）。
        var levels: [Int: [Int]] = [:]
        // 最近标题节点的索引路径（列表项挂这里）；nil = 尚无标题（列表丢弃）。
        var lastHeadingPath: [Int]?

        func clean(_ raw: Substring) -> String {
            let t = String(raw).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "未命名" : t
        }

        // 沿索引路径（相对 root 的 children 下标链）定位父节点并 append，返回新节点路径。
        func appendChild(_ child: Node, to path: ArraySlice<Int>, in node: inout Node) -> [Int] {
            if let head = path.first {
                let childPath = appendChild(child, to: path.dropFirst(), in: &node.children[head])
                return [head] + childPath
            }
            node.children.append(child)
            return [node.children.count - 1]
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // —— 标题行 #…
            if trimmed.hasPrefix("#") {
                // 连续 # 个数 = 深度；`# #`（# 后紧跟 # 不空格）按连续 # 计，非标题不跳过。
                let depth = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(depth).trimmingCharacters(in: .whitespaces)
                headingCount += 1
                let capped = min(max(depth, 1), 6)
                // 空标题（`#` 后无文案）→「未命名」节点（spec §3.2：空标题/空列表项 → 未命名）
                let node = Node(text: clean(Substring(rest)))

                if root == nil {
                    root = node
                    levels[1] = []
                    lastHeadingPath = []
                } else {
                    // 父 = 小于 capped 的最近已存在层级；无则挂根（跳级直连 / 首个标题后首个深标题）。
                    var parentPath: [Int] = []
                    for d in stride(from: capped - 1, through: 1, by: -1) {
                        if let candidate = levels[d] { parentPath = candidate; break }
                    }
                    let childPath = appendChild(node, to: parentPath[...], in: &root!)
                    // 记录 depth=capped，清空更深的各级（后续标题不再挂到旧深层下）。
                    levels[capped] = childPath
                    for d in levels.keys where d > capped { levels[d] = nil }
                    lastHeadingPath = childPath
                }
                continue
            }

            // —— 列表项 - / * / •
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let item = Node(text: content.isEmpty ? "未命名" : content)
                if let path = lastHeadingPath {
                    _ = appendChild(item, to: path[...], in: &root!)   // 首个标题前 → lastHeadingPath 为 nil → 丢弃
                }
                continue
            }

            // —— 其它行（空行 / 纯段落）：忽略
        }

        guard let root, headingCount > 0 else {
            throw ImportError.unrecognizedOutline
        }

        // 根直接子 side 交替分配（先 left 后 right 均衡）
        var result = root
        for (index, _) in result.children.enumerated() {
            result.children[index].side = (index % 2 == 0) ? .left : .right
        }
        return MindMapDocument(version: MindMapDocument.currentVersion, root: result)
    }
}