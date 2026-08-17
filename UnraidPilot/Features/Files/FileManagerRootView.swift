import SwiftUI

struct FileManagerRootView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var store = SMBFileStore()

    var body: some View {
        Group {
            if store.isConfigured {
                SMBDirectoryView(store: store, path: "/", title: store.configuration.share)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("断开文件共享", role: .destructive) { try? store.disconnect() }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
            } else {
                SMBSetupView(store: store)
            }
        }
        .navigationTitle("文件管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.configuration.host.isEmpty { store.configuration.host = session.serverHost }
        }
    }
}

private struct SMBSetupView: View {
    @ObservedObject var store: SMBFileStore
    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Label("使用 Unraid 共享用户通过 SMB2/3 连接。无需 root 密码。", systemImage: "lock.shield.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("共享服务器") {
                TextField("主机名或 IP", text: $store.configuration.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("共享名称，例如 media", text: $store.configuration.share).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("共享用户") {
                TextField("用户名", text: $store.configuration.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $store.password)
            }
            Section {
                Button {
                    Task {
                        connecting = true; defer { connecting = false }
                        do { try await store.configure(); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack { Spacer(); if connecting { ProgressView() }; Text(connecting ? "正在连接…" : "连接文件共享"); Spacer() }
                }
                .disabled(connecting)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .alert("无法连接文件共享", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}
