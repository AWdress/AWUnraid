import SwiftUI

struct SystemLogsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var files: [LogFileItem] = []
    @State private var error: String?

    var body: some View {
        List(files) { file in
            NavigationLink { LogFileView(file: file) } label: {
                VStack(alignment: .leading) { Text(file.name); Text("\(file.size) bytes · \(file.modifiedAt)").font(.caption).foregroundStyle(.secondary) }
            }
        }.scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("系统日志").task { await load() }.refreshable { await load() }
    }
    private func load() async { do { files = try await session.logFiles() } catch { self.error = error.localizedDescription } }
}

private struct LogFileView: View {
    @EnvironmentObject private var session: AppSession
    let file: LogFileItem
    @State private var content = "正在读取…"
    var body: some View {
        ScrollView([.vertical, .horizontal]) { Text(content).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
            .background(Color.black.ignoresSafeArea()).navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
            .task { content = (try? await session.logFile(path: file.path)) ?? "读取失败" }
    }
}
