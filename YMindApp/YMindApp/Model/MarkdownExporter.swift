import Foundation

/// 整棵逻辑树 → Markdown 大纲（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历。
/// 标题按「层级」对齐而非按单个节点：
/// 从根向下直到「最深的含分支节点（有子节点）的层」都渲染为标题（`#`×depth，depth>6 用 `######`）；
/// 其下纯叶子层渲染为内容列表项（不缩进，符号按深度循环 - / * / +）。
/// 理由：同一层只要有任一分支，该层就应全为标题（兄弟节点类型一致，层级不错乱）。
/// 根节点恒为标题（即使无子节点）。
enum MarkdownExporter {
    /// 叶子列表符号按深度循环：深度2→`-`、3→`*`、4→`+`、5→`-`…
    private static let leafSymbols = ["-", "*", "+"]

    /// 深度 1 = 中心主题；子节点 +1。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        let lastHeadingLevel = max(deepestBranchLevel(of: document.root), 1)
        var lines: [String] = []
        walk(document.root, depth: 1, lastHeadingLevel: lastHeadingLevel, into: &lines)
        return lines.joined(separator: "\n\n") + "\n"
    }

    /// 树中最深的「含子节点」的层（root 深度为 1；无子节点返回 0）。
    private static func deepestBranchLevel(of node: Node, depth: Int = 1) -> Int {
        if node.children.isEmpty { return 0 }
        var deepest = depth
        for child in node.children {
            deepest = max(deepest, deepestBranchLevel(of: child, depth: depth + 1))
        }
        return deepest
    }

    private static func walk(_ node: Node, depth: Int, lastHeadingLevel: Int, into lines: inout [String]) {
        if depth <= lastHeadingLevel {
            let level = min(max(depth, 1), 6)
            lines.append("\(String(repeating: "#", count: level)) \(collapsedText(node.text))")
        } else {
            let symbol = leafSymbols[(depth - 2) % leafSymbols.count]
            lines.append("\(symbol) \(collapsedText(node.text))")
        }
        for child in node.children {
            walk(child, depth: depth + 1, lastHeadingLevel: lastHeadingLevel, into: &lines)
        }
    }

    /// 对齐原型 treeToMarkdown：\r\n → \n，按行 trim，去空行，join 空格。
    static func collapsedText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "未命名" : collapsed
    }
}
