import SwiftUI

struct FileManagerRootView: View {
    @EnvironmentObject private var session: AppSession
    @State private var store: RemoteFileStore?
    @State private var setupError: String?

    var body: some View {
        Group {
            if let store {
                FileConnectionContent(store: store) {
                    Task { await connect() }
                }
            } else {
                ProgressView("正在准备文件服务…")
            }
        }
        .background(AppTheme.background)
        .navigationTitle("文件")
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
        .alert("无法启动文件管理", isPresented: Binding(get: { setupError != nil }, set: { if !$0 { setupError = nil } })) {
            Button("好") { setupError = nil }
        } message: { Text(setupError ?? "") }
    }

    private func connect() async {
        do {
            let activeStore: RemoteFileStore
            if let store {
                activeStore = store
            } else {
                activeStore = try session.makeRemoteFileStore()
            }
            store = activeStore
            await activeStore.connect()
        } catch {
            setupError = error.localizedDescription
        }
    }
}

private struct FileConnectionContent: View {
    @ObservedObject var store: RemoteFileStore
    let retry: () -> Void

    var body: some View {
        if store.isConnected {
            RemoteDirectoryView(store: store, path: "/", title: "文件")
        } else if store.isConnecting {
            ProgressView("正在连接文件服务…")
        } else {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.accent)
                Text("文件服务未连接").font(.headline)
                Text(store.errorMessage ?? "请在 Unraid 安装 AW Companion。App 会复用当前服务器地址和 API Key，不需要再次登录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重新检测", action: retry)
            }
            .padding(28)
        }
    }
}
