import Foundation

/// 导出文件名规整（对齐原型 safeFilename）。仅字符串处理，无 UI 依赖。
enum ExportNaming {
    static func safeFilename(base: String?, ext: String) -> String {
        let illegal = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let name = (base ?? "ymind")
            .components(separatedBy: illegal)
            .joined(separator: "_")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = String(trimmed.prefix(48)).isEmpty ? "ymind" : String(trimmed.prefix(48))
        return "\(finalName).\(ext)"
    }
}
