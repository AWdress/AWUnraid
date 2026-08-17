import SwiftUI

struct VirtualMachinesView: View {
    @EnvironmentObject private var session: AppSession
    @State private var pending: (VirtualMachineSnapshot, VirtualMachineAction)?

    var body: some View {
        Group {
            if session.server.virtualMachines.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("没有可管理的虚拟机").font(.headline)
                    Text("服务器可能尚未启用 VM Manager，或当前没有创建虚拟机。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(session.server.virtualMachines) { vm in
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading) { Text(vm.name).font(.headline); Text(stateText(vm.state)).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Circle().fill(vm.state == .running ? AppTheme.healthy : Color.secondary).frame(width: 8, height: 8)
                    }
                    .contextMenu {
                        Button("启动") { pending = (vm, .start) }
                        Button("正常关机") { pending = (vm, .stop) }
                        Button(vm.state == .paused ? "恢复" : "暂停") { pending = (vm, vm.state == .paused ? .resume : .pause) }
                        Button("重启") { pending = (vm, .reboot) }
                        Button("强制停止", role: .destructive) { pending = (vm, .forceStop) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.background).navigationTitle("虚拟机")
        .confirmationDialog(pending.map { "操作 \($0.0.name)" } ?? "虚拟机操作", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("确认", role: pending?.1 == .forceStop ? .destructive : nil) {
                let operation = pending; pending = nil
                if let operation { Task { await session.perform(operation.1, vmID: operation.0.id) } }
            }
            Button("取消", role: .cancel) { pending = nil }
        }
    }

    private func stateText(_ state: VirtualMachineSnapshot.State) -> String {
        switch state {
        case .running: return "运行中"
        case .paused: return "已暂停"
        case .stopped: return "已停止"
        case .unknown: return "未知"
        }
    }
}
