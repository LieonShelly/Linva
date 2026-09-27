import Foundation

/// 5 个具名预设填色 token；nil = 默认外观（PRD FR-C1）。
enum NodeFill: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case sage, sky, sand, rose, lilac
}
