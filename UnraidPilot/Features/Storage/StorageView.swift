import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var session: AppSession
    @State private var pendingArrayAction: ArrayAction?
    @State private var pendingParityAction: ParityAction?
    var body: some View {
        List {
            Section("阵列") {
                LabeledContent("状态", value: session.server.arrayStarted ? "已启动" : "已停止")
                LabeledContent("容量", value: String(format: "%.2f / %.2f TB", session.server.arrayUsedTB, session.server.arrayTotalTB))
                Button(session.server.arrayStarted ? "停止阵列" : "启动阵列", role: session.server.arrayStarted ? .destructive : nil) {
                    pendingArrayAction = session.server.arrayStarted ? .stop : .start
                }
            }
            Section("Parity") {
                LabeledContent("状态", value: session.server.parityRunning ? "校验中" : (session.server.parityValid ? "有效" : "需要校验"))
                if session.server.parityRunning {
                    ProgressView(value: session.server.parityProgress)
                    Button("暂停校验") { pendingParityAction = .pause }
                    Button("取消校验", role: .destructive) { pendingParityAction = .cancel }
                } else {
                    Button("开始只读校验") { pendingParityAction = .start(correcting: false) }
                    Button("开始校正校验") { pendingParityAction = .start(correcting: true) }
                }
            }
            Section("磁盘") {
                ForEach(session.server.disks) { disk in
                    HStack { Image(systemName: "internaldrive.fill"); VStack(alignment: .leading) { Text(disk.name); Text(disk.model).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(disk.temperature)°C") }
                }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("存储")
        .confirmationDialog("确认阵列操作", isPresented: Binding(get: { pendingArrayAction != nil }, set: { if !$0 { pendingArrayAction = nil } }), titleVisibility: .visible) {
            Button(pendingArrayAction == .stop ? "停止阵列" : "启动阵列", role: pendingArrayAction == .stop ? .destructive : nil) {
                let action = pendingArrayAction; pendingArrayAction = nil
                if let action { Task { await session.perform(action) } }
            }
            Button("取消", role: .cancel) { pendingArrayAction = nil }
        } message: { Text("阵列操作会影响共享、Docker 和虚拟机。") }
        .confirmationDialog("确认 Parity 操作", isPresented: Binding(get: { pendingParityAction != nil }, set: { if !$0 { pendingParityAction = nil } }), titleVisibility: .visible) {
            Button("继续") {
                let action = pendingParityAction; pendingParityAction = nil
                if let action { Task { await session.perform(action) } }
            }
            Button("取消", role: .cancel) { pendingParityAction = nil }
        }
    }
}
