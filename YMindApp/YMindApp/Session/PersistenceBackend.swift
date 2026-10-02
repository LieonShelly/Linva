// YMindApp/YMindApp/Session/PersistenceBackend.swift
import Foundation

/// 持久化后端抽象（DIP）：读写字节。未来云同步实现同一协议，本地 scope 语义由 DocumentPersistence 处理。
protocol PersistenceBackend {
    func readData(from url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
}

/// 本地文件持久化：纯字节读写（原子写）。
final class YMindFilePersistence: PersistenceBackend {
    func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// 沙盒安全作用域读写封装（start/stop 平衡，持有当前 URL 的 scope）。原样迁自 DocumentSession.swift。
final class SecurityScopedAccess {
    typealias StartAccess = (URL) -> Bool
    typealias StopAccess = (URL) -> Void

    private let startAccess: StartAccess
    private let stopAccess: StopAccess
    private var activeURL: URL?

    init(
        startAccess: @escaping StartAccess = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping StopAccess = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.startAccess = startAccess
        self.stopAccess = stopAccess
    }

    deinit {
        release()
    }

    func replace<T>(with url: URL, operation: () throws -> T) rethrows -> T {
        if activeURL == url {
            return try operation()
        }
        let didStart = startAccess(url)
        do {
            let result = try operation()
            release()
            if didStart {
                activeURL = url
            }
            return result
        } catch {
            if didStart {
                stopAccess(url)
            }
            throw error
        }
    }

    func withAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        if activeURL == url {
            return try operation()
        }
        let didStart = startAccess(url)
        defer {
            if didStart {
                stopAccess(url)
            }
        }
        return try operation()
    }

    func release() {
        guard let activeURL else { return }
        stopAccess(activeURL)
        self.activeURL = nil
    }
}
