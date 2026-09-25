import Foundation

enum ClipboardMode: Equatable {
    case copy
    case cut
}

struct ClipboardPayload: Equatable {
    let mode: ClipboardMode
    let nodes: [Node]      // 深拷贝快照
    let sourceIds: [UUID]  // cut 模式：源 ID
}
