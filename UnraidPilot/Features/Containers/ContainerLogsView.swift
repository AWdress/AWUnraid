import SwiftUI

struct ContainerLogsView: View {
    @EnvironmentObject private var session: AppSession
    let container: ContainerSnapshot
    @State private var lines: [String] = []
    @State private var error: String?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(lines.isEmpty ? "正在读取日志…" : lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(container.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("日志读取失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }

    private func load() async {
        do { lines = try await session.containerLogs(id: container.id) }
        catch { self.error = error.localizedDescription }
    }
}
