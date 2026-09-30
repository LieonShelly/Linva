import SwiftUI

/// 崩溃恢复横幅：显示「检测到上次未保存的更改」+ 文档名/时间/修改数 + 恢复/忽略。
struct RecoveryBannerView: View {
    let offer: RecoveryOffer
    let onRestore: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到上次未保存的更改")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("忽略（丢弃草稿）") { onDiscard() }
            Button("恢复更改") { onRestore() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
        .accessibilityLabel("检测到上次未保存的更改")
    }

    private var summary: String {
        let name = offer.meta.rootText ?? "未命名文档"
        var parts: [String] = []
        parts.append("「\(name)」")
        if let url = offer.meta.originalURL, let u = URL(string: url) {
            parts.append(u.lastPathComponent)
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        parts.append("最近自动保存 \(formatter.string(from: offer.meta.savedAt))")
        parts.append("\(offer.meta.changeCount) 处修改未写盘")
        return parts.joined(separator: " · ")
    }
}