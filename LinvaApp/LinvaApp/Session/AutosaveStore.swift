// Session/AutosaveStore.swift
import Foundation

/// 临时副本配对元信息（随副本落盘，不写入文档本身）。
struct AutosaveMeta: Codable, Equatable {
    var documentID: UUID        // 内存会话 uuid（未命名文档亦然）
    var originalURL: String?    // 正式文件 URL 的 absoluteString（nil=未命名）
    var savedAt: Date           // 最近自动保存时间
    var changeCount: Int        // 距上次写盘的变化次数
    var rootText: String?       // 供横幅显示文档名
}

/// 管理 Application Support/Unsaved/ 下的临时副本；不接触 Model / 命令栈。
/// directory 可注入（测试用临时目录）；默认惰性取 Application Support/Unsaved。
final class AutosaveStore {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Unsaved", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func docURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).linva") }
    private func metaURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).meta.json") }

    /// 写副本（文档 JSON + meta JSON）。失败抛出（Session 侧静默吞掉）。
    func write(document: MindMapDocument, meta: AutosaveMeta) throws {
        let docData = try LinvaCodec.encode(document)
        try docData.write(to: docURL(meta.documentID), options: .atomic)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaURL(meta.documentID), options: .atomic)
    }

    /// 删除某文档的副本（.linva + .meta.json）。不存在时静默。
    func delete(documentID: UUID) throws {
        try? FileManager.default.removeItem(at: docURL(documentID))
        try? FileManager.default.removeItem(at: metaURL(documentID))
    }

    /// 扫描目录：返回 savedAt 最新的 meta（nil = 无副本）。
    func latestPending() -> AutosaveMeta? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let metas = files.filter { $0.hasSuffix(".meta.json") }.compactMap { name -> AutosaveMeta? in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AutosaveMeta.self, from: data)
        }
        return metas.max { $0.savedAt < $1.savedAt }
    }

    /// 「忽略」清空整个 Unsaved/（含历史残留与无 meta 的孤儿文件）。
    func clearAll() throws {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// 读回某副本文档 JSON（Decode → MindMapDocument）。
    func load(documentID: UUID) throws -> MindMapDocument {
        let data = try Data(contentsOf: docURL(documentID))
        return try LinvaCodec.decode(data)
    }
}