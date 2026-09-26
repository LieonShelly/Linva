import SwiftUI

struct SearchBar: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label("搜索", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索主题…", text: Binding(
                get: { session.search.query },
                set: { session.runSearch(query: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onSubmit { session.revealSearchMatch(session.search.index + 1) }
            .onExitCommand { session.closeSearch() }

            Text("\(session.search.index + 1) / \(session.search.matches.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("搜索计数")

            Button { session.revealSearchMatch(session.search.index - 1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(session.search.matches.isEmpty)
            .help("上一项（⇧Enter）")

            Button { session.revealSearchMatch(session.search.index + 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(session.search.matches.isEmpty)
            .help("下一项（Enter）")

            Button { session.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .help("关闭（Esc）")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
        .onChange(of: session.search.currentMatchId) { _, newId in
            guard let newId else { return }
            if let size = windowSize() {
                session.centerCamera(on: newId, viewport: size)
            }
        }
    }

    private func windowSize() -> CGSize? {
        NSApp.keyWindow?.contentView?.bounds.size
    }
}
