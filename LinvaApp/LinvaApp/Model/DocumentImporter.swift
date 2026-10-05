import Foundation

/// 导入失败的统一错误（可读，中止导入且不改当前文档）。
enum ImportError: Error, Equatable {
    case unrecognizedOutline   // Markdown：整文件无任何标题
    case invalidXML            // OPML/FreeMind：非法 XML 或空根
}

/// 把外部格式 Data 解析为新的 MindMapDocument（纯函数，无副作用）。
protocol DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument
}

/// 按文件扩展名路由到具体导入器（XMind 后续在此注册，v1.1）。
enum DocumentImporterRegistry {
    static let markdown = MarkdownImporter()
    static let opml = OPMLImporter()
    static let freeMind = FreeMindImporter()

    /// 大小写不敏感；未知扩展名返回 nil。
    static func importer(for pathExtension: String) -> DocumentImporter? {
        switch pathExtension.lowercased() {
        case "md", "markdown": return markdown
        case "opml": return opml
        case "mm": return freeMind
        default: return nil
        }
    }
}