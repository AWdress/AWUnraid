import SwiftUI

struct ContainerSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let containerID: String
    @State private var autoStart = false
    @State private var waitSeconds = 0
    @State private var includeImage = false
    @State private var confirmsRemoval = false
    @State private var initialized = false

    private var container: ContainerSnapshot? { session.server.containers.first { $0.id == containerID } }

    var body: some View {
        Form {
            Section("自动启动") {
                Toggle("随阵列自动启动", isOn: $autoStart)
                if autoStart {
                    Stepper("启动后等待 \(waitSeconds) 秒", value: $waitSeconds, in: 0...300, step: 5)
                }
                Button("保存自动启动设置") {
                    Task { await session.setContainerAutoStart(id: containerID, enabled: autoStart, wait: autoStart ? waitSeconds : nil) }
                }
            }

            Section {
                LabeledContent("镜像", value: container?.image ?? "—")
                LabeledContent("网络模式", value: container?.networkMode ?? "—")
                LabeledContent("启动顺序", value: container?.autoStartOrder.map(String.init) ?? "自动")
            } header: {
                Text("运行配置")
            } footer: {
                Text("Unraid GraphQL 当前支持读取运行配置，但不提供修改端口、挂载和环境变量的接口。")
            }

            Section("危险区域") {
                Toggle("同时删除镜像", isOn: $includeImage)
                Button("删除容器", role: .destructive) { confirmsRemoval = true }
            }
        }
        .navigationTitle("容器设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized, let container else { return }
            initialized = true
            autoStart = container.autoStart
            waitSeconds = container.autoStartWait ?? 0
        }
        .confirmationDialog("永久删除 \(container?.name ?? "容器")？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button(includeImage ? "删除容器和镜像" : "删除容器", role: .destructive) {
                Task {
                    await session.removeContainer(id: containerID, withImage: includeImage)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。挂载在主机路径中的数据不会被删除。")
        }
    }
}
