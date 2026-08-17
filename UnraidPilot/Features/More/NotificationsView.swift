import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var items: [AppNotification] = []
    @State private var error: String?

    var body: some View {
        List(items) { item in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.importance.uppercased().contains("ALERT") ? "exclamationmark.triangle.fill" : "bell.fill")
                    .foregroundStyle(item.importance.uppercased().contains("ALERT") ? AppTheme.warning : AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.headline); Text(item.detail).font(.subheadline).foregroundStyle(.secondary); Text(item.timestamp).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .overlay {
            if items.isEmpty && error == nil {
                VStack(spacing: 10) { Image(systemName: "checkmark.shield.fill").font(.largeTitle).foregroundStyle(AppTheme.healthy); Text("暂无告警").font(.headline) }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("通知")
        .task { await load() }.refreshable { await load() }
        .alert("读取失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func load() async { do { items = try await session.notifications() } catch { self.error = error.localizedDescription } }
}
