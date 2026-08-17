import SwiftUI

struct ContainerDetailView: View {
    @EnvironmentObject private var session: AppSession
    let containerID: String
    @State private var pendingAction: ContainerAction?

    private var container: ContainerSnapshot? {
        session.server.containers.first { $0.id == containerID }
    }

    var body: some View {
        Group {
            if let container {
                List {
                    Section { header(container).listRowBackground(Color.clear) }
                    Section("操作") { actions(container) }
                    Section("管理") {
                        NavigationLink { ContainerLogsView(container: container) } label: {
                            Label("日志", systemImage: "text.alignleft")
                        }
                        NavigationLink { ContainerSettingsView(containerID: container.id) } label: {
                            Label("容器设置", systemImage: "gearshape.fill")
                        }
                        if let webURL = container.webUIURL {
                            Link(destination: webURL) { Label("打开容器 WebUI", systemImage: "safari") }
                        }
                    }
                    Section("运行信息") {
                        DetailRow(label: "状态", value: container.status.isEmpty ? stateText(container.state) : container.status)
                        DetailRow(label: "镜像", value: container.image)
                        DetailRow(label: "网络模式", value: container.networkMode)
                        DetailRow(label: "自动启动", value: container.autoStart ? "已开启" : "已关闭")
                        if container.updateAvailable { DetailRow(label: "镜像更新", value: "有新版本", tint: AppTheme.warning) }
                        if container.isOrphaned { DetailRow(label: "模板状态", value: "孤儿容器", tint: AppTheme.warning) }
                    }
                    if !container.ports.isEmpty {
                        Section("端口映射") {
                            ForEach(container.ports) { port in
                                DetailRow(label: "\(port.type.uppercased()) · \(port.privatePort.map(String.init) ?? "—")", value: port.publicPort.map(String.init) ?? "未映射")
                            }
                        }
                    }
                    if !container.mounts.isEmpty {
                        Section("存储挂载") {
                            ForEach(container.mounts) { mount in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(mount.destination).font(.body.weight(.medium))
                                    Text(mount.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text(mount.readOnly ? "只读 · \(mount.type)" : "读写 · \(mount.type)")
                                        .font(.caption2).foregroundStyle(mount.readOnly ? AppTheme.warning : .secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    Section("占用空间") {
                        DetailRow(label: "镜像与根文件系统", value: formatBytes(container.rootSize))
                        DetailRow(label: "可写层", value: formatBytes(container.writableSize))
                        DetailRow(label: "日志", value: formatBytes(container.logSize), tint: container.logSize > 100_000_000 ? AppTheme.warning : nil)
                    }
                    if !container.command.isEmpty {
                        Section("启动命令") {
                            Text(container.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .refreshable { await session.refresh() }
                .confirmationDialog("操作 \(container.name)", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                    Button(actionTitle(pendingAction), role: pendingAction == .stop ? .destructive : nil) {
                        let action = pendingAction
                        pendingAction = nil
                        if let action { Task { await session.perform(action, containerID: container.id) } }
                    }
                    Button("取消", role: .cancel) { pendingAction = nil }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox").font(.largeTitle).foregroundStyle(.secondary)
                    Text("容器不存在").font(.headline)
                    Text("它可能已经被删除。").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(container?.name ?? "容器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ container: ContainerSnapshot) -> some View {
        HStack(spacing: 16) {
            ContainerIconView(container: container, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(container.name).font(.title2.bold())
                Text(container.image).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Label(stateText(container.state), systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(container.state == .running ? AppTheme.healthy : .secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func actions(_ container: ContainerSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ActionButton(title: container.state == .running ? "停止" : "启动", icon: container.state == .running ? "stop.fill" : "play.fill", tint: container.state == .running ? .red : AppTheme.healthy) {
                    pendingAction = container.state == .running ? .stop : .start
                }
                ActionButton(title: "重启", icon: "arrow.clockwise", tint: AppTheme.accent) { pendingAction = .restart }
                ActionButton(title: container.state == .paused ? "恢复" : "暂停", icon: container.state == .paused ? "playpause.fill" : "pause.fill", tint: AppTheme.accent) {
                    pendingAction = container.state == .paused ? .resume : .pause
                }
                ActionButton(title: "更新", icon: "arrow.up.circle.fill", tint: container.updateAvailable ? AppTheme.warning : AppTheme.accent) { pendingAction = .update }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))
    }

    private func stateText(_ state: ContainerSnapshot.State) -> String {
        switch state { case .running: return "运行中"; case .paused: return "已暂停"; case .stopped: return "已停止" }
    }

    private func actionTitle(_ action: ContainerAction?) -> String {
        switch action { case .start: return "启动"; case .stop: return "停止"; case .pause: return "暂停"; case .resume: return "恢复"; case .restart: return "重启"; case .update: return "更新"; case nil: return "确认" }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .buttonBorderShape(.capsule)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var tint: Color?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).foregroundStyle(tint ?? .primary).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}
