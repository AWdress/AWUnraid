import SwiftUI

struct ContainersView: View {
    @EnvironmentObject private var session: AppSession
    @State private var pending: (ContainerSnapshot, ContainerAction)?
    @State private var searchText = ""
    @State private var sort = Sort.name
    @State private var confirmsUpdateAll = false

    private enum Sort: String, CaseIterable, Identifiable {
        case name = "名称"
        case state = "状态"
        case update = "可更新"
        var id: Self { self }
    }

    private var visibleContainers: [ContainerSnapshot] {
        let filtered = session.server.containers.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.image.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .state: return filtered.sorted { $0.state.rawValue < $1.state.rawValue }
        case .update: return filtered.sorted { $0.updateAvailable && !$1.updateAvailable }
        }
    }

    private var needsAttention: [ContainerSnapshot] { visibleContainers.filter { $0.updateAvailable || $0.isOrphaned } }
    private var regular: [ContainerSnapshot] { visibleContainers.filter { !$0.updateAvailable && !$0.isOrphaned } }

    var body: some View {
        List {
            Section { statusSummary.listRowInsets(.init()).listRowBackground(Color.clear) }

            if !needsAttention.isEmpty {
                Section("需要处理") {
                    ForEach(needsAttention) { row(for: $0) }
                }
            }

            Section(needsAttention.isEmpty ? "容器" : "其他容器") {
                ForEach(regular) { row(for: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Docker")
        .searchable(text: $searchText, prompt: "搜索容器或镜像")
        .refreshable { await session.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }

                Menu {
                    Button("检查并更新全部", systemImage: "arrow.triangle.2.circlepath") { confirmsUpdateAll = true }
                    Button("刷新状态", systemImage: "arrow.clockwise") { Task { await session.refresh() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog(
            pending.map { "操作 \($0.0.name)" } ?? "容器操作",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button(actionTitle(pending?.1), role: pending?.1 == .stop ? .destructive : nil) {
                let operation = pending
                pending = nil
                if let operation { Task { await session.perform(operation.1, containerID: operation.0.id) } }
            }
            Button("取消", role: .cancel) { pending = nil }
        }
        .confirmationDialog("检查并更新所有容器？", isPresented: $confirmsUpdateAll, titleVisibility: .visible) {
            Button("更新全部") { Task { await session.updateAllContainers() } }
            Button("取消", role: .cancel) {}
        } message: { Text("运行中的容器可能会在更新过程中短暂重启。") }
    }

    private var statusSummary: some View {
        let running = session.server.containers.filter { $0.state == .running }.count
        let stopped = session.server.containers.filter { $0.state == .stopped }.count
        let updates = session.server.containers.filter(\.updateAvailable).count
        let total = max(session.server.containers.count, 1)

        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    Capsule().fill(AppTheme.healthy).frame(width: proxy.size.width * CGFloat(running) / CGFloat(total))
                    Capsule().fill(Color.secondary.opacity(0.45)).frame(width: proxy.size.width * CGFloat(stopped) / CGFloat(total))
                    if updates > 0 { Capsule().fill(AppTheme.warning).frame(width: min(proxy.size.width * 0.18, 64)) }
                }
            }
            .frame(height: 6)

            HStack(spacing: 14) {
                StatusCount(color: AppTheme.healthy, text: "运行 \(running)")
                StatusCount(color: .secondary, text: "已停止 \(stopped)")
                if updates > 0 { StatusCount(color: AppTheme.warning, text: "可更新 \(updates)") }
            }
            .font(.caption.weight(.medium))
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func row(for container: ContainerSnapshot) -> some View {
        HStack(spacing: 12) {
            NavigationLink { ContainerDetailView(containerID: container.id) } label: {
                HStack(spacing: 12) {
                    ContainerIconView(container: container)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.name).font(.headline).lineLimit(1)
                        if container.updateAvailable {
                            Label("可更新", systemImage: "arrow.up.circle.fill")
                                .font(.caption).foregroundStyle(AppTheme.warning)
                        } else {
                            Text(container.status.isEmpty ? stateText(container.state) : container.status)
                                .font(.caption).foregroundStyle(container.state == .running ? AppTheme.healthy : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Button {
                pending = (container, container.state == .running ? .stop : .start)
            } label: {
                Image(systemName: container.state == .running ? "stop.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.13), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(container.state == .running ? "停止 \(container.name)" : "启动 \(container.name)")
        }
        .contextMenu { actionMenu(for: container) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("重启") { pending = (container, .restart) }.tint(AppTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(container.state == .running ? "停止" : "启动") {
                pending = (container, container.state == .running ? .stop : .start)
            }
            .tint(container.state == .running ? .red : AppTheme.healthy)
        }
    }

    @ViewBuilder
    private func actionMenu(for container: ContainerSnapshot) -> some View {
        Button("启动", systemImage: "play.fill") { pending = (container, .start) }
        Button("停止", systemImage: "stop.fill", role: .destructive) { pending = (container, .stop) }
        Button(container.state == .paused ? "恢复" : "暂停", systemImage: container.state == .paused ? "playpause.fill" : "pause.fill") {
            pending = (container, container.state == .paused ? .resume : .pause)
        }
        Button("重启", systemImage: "arrow.clockwise") { pending = (container, .restart) }
        Button("更新", systemImage: "arrow.up.circle") { pending = (container, .update) }
    }

    private func stateText(_ state: ContainerSnapshot.State) -> String {
        switch state { case .running: return "运行中"; case .paused: return "已暂停"; case .stopped: return "已停止" }
    }

    private func actionTitle(_ action: ContainerAction?) -> String {
        switch action {
        case .start: return "启动"
        case .stop: return "停止"
        case .pause: return "暂停"
        case .resume: return "恢复"
        case .restart: return "重启"
        case .update: return "更新"
        case nil: return "确认"
        }
    }
}

private struct StatusCount: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(text) }
    }
}
