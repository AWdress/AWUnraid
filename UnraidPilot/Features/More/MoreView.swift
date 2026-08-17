import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var session: AppSession
    @State private var confirmsDisconnect = false
    @State private var disconnectError: String?

    var body: some View {
        List {
            Section("管理") {
                NavigationLink { VirtualMachinesView() } label: { Label("虚拟机", systemImage: "desktopcomputer") }
                NavigationLink { NotificationsView() } label: { Label("通知", systemImage: "bell.fill") }
                NavigationLink { SystemLogsView() } label: { Label("系统日志", systemImage: "doc.text.fill") }
                if let url = session.webConsoleURL {
                    NavigationLink { WebAdminView(url: url) } label: {
                        Label("完整 Web 管理台", systemImage: "safari.fill")
                    }
                }
            }
            Section("服务器") {
                NavigationLink { ServerSettingsView() } label: { Label("连接设置", systemImage: "gearshape.fill") }
                Button("断开并清除凭据", role: .destructive) { confirmsDisconnect = true }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("更多")
        .confirmationDialog("清除此设备上的连接信息和 API Key？", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                do { try session.disconnect() } catch { disconnectError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("无法清除凭据", isPresented: Binding(get: { disconnectError != nil }, set: { if !$0 { disconnectError = nil } })) {
            Button("好") { disconnectError = nil }
        } message: { Text(disconnectError ?? "未知错误") }
    }
}
