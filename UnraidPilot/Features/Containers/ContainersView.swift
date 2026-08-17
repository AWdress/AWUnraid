import SwiftUI

struct ContainersView: View {
    @EnvironmentObject private var session: AppSession
    @State private var pending: (ContainerSnapshot, ContainerAction)?
    var body: some View {
        List(session.server.containers) { container in
            NavigationLink { ContainerLogsView(container: container) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill").foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading) { Text(container.name).font(.headline); Text(container.image).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(container.state == .running ? "运行中" : "已停止").foregroundStyle(container.state == .running ? AppTheme.healthy : .secondary)
                }
            }
            .swipeActions {
                Button("重启") { pending = (container, .restart) }.tint(AppTheme.accent)
                if container.state == .running { Button("停止") { pending = (container, .stop) }.tint(.red) }
                else { Button("启动") { pending = (container, .start) }.tint(AppTheme.healthy) }
            }
            .contextMenu {
                Button("启动") { pending = (container, .start) }
                Button("停止", role: .destructive) { pending = (container, .stop) }
                Button(container.state == .paused ? "恢复" : "暂停") { pending = (container, container.state == .paused ? .resume : .pause) }
                Button("重启") { pending = (container, .restart) }
                Button("更新容器") { pending = (container, .update) }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("Docker")
        .confirmationDialog(pending.map { "操作 \($0.0.name)" } ?? "容器操作", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("确认", role: pending?.1 == .stop ? .destructive : nil) {
                let operation = pending; pending = nil
                if let operation { Task { await session.perform(operation.1, containerID: operation.0.id) } }
            }
            Button("取消", role: .cancel) { pending = nil }
        }
    }
}
