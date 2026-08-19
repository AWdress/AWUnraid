import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    var isOnboarding = false

    @State private var name = "Tower"
    @State private var address = ""
    @State private var graphQLPath = "/graphql"
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var showsAdvanced = false
    @State private var isConnecting = false
    @State private var message: String?
    @State private var hasLoadedConfiguration = false

    private enum Field { case name, address, apiKey, graphQLPath }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if isOnboarding { welcomeHeader }
                connectionFields
                credentialFields
                advancedSettings
                connectButton
                securityNote
            }
            .padding(.horizontal, 20)
            .padding(.top, isOnboarding ? 24 : 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(isOnboarding ? "" : "连接设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .task { loadCurrentConfiguration() }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 8) {
                Text("连接你的 Unraid")
                    .font(.largeTitle.bold())
                Text("支持局域网地址或 HTTPS 远程反代，粘贴完整 GraphQL 链接即可。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionFields: some View {
        SettingsGroup(title: "服务器") {
            ConnectionField(title: "名称", placeholder: "例如 Tower", icon: "server.rack", text: $name)
                .focused($focusedField, equals: .name)
            Divider().overlay(AppTheme.divider).padding(.leading, 44)
            ConnectionField(title: "Unraid API 地址", placeholder: "https://nas.example.com/graphql", icon: "network", text: $address, keyboardType: .URL)
                .focused($focusedField, equals: .address)
        }
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("认证").font(.headline)
            HStack(spacing: 14) {
                Image(systemName: "key.fill")
                    .frame(width: 30)
                    .foregroundStyle(AppTheme.accent)
                SecureField(session.hasStoredAPIKey ? "留空则继续使用已保存的 API Key" : "粘贴 API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .apiKey)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("API Key 只保存在这台 iPhone 的系统钥匙串中。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(spacing: 0) {
                ConnectionField(title: "GraphQL 路径", placeholder: "/graphql", icon: "point.3.connected.trianglepath.dotted", text: $graphQLPath)
                    .focused($focusedField, equals: .graphQLPath)
                Divider().overlay(AppTheme.divider).padding(.leading, 44)
                Toggle(isOn: $allowSelfSigned) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("忽略服务器证书校验")
                        Text("仅用于自签名 HTTPS；会降低连接安全性")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppTheme.warning)
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
            }
            .padding(.top, 8)
        } label: {
            Label("高级连接设置", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var connectButton: some View {
        VStack(spacing: 12) {
            Button {
                focusedField = nil
                Task { await save() }
            } label: {
                HStack(spacing: 10) {
                    if isConnecting { ProgressView().tint(.white) }
                    Text(isConnecting ? "正在验证服务器…" : "连接服务器").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle)
            .tint(AppTheme.accent)
            .disabled(isConnecting || (!session.hasStoredAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var securityNote: some View {
        Label("AW Unraid 不会上传你的服务器地址或 API Key。", systemImage: "lock.shield.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func save() async {
        var cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAddress.contains("://") { cleanAddress = "https://\(cleanAddress)" }
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let enteredURL = URL(string: cleanAddress), enteredURL.scheme == "http" || enteredURL.scheme == "https" else {
            message = "服务器地址需要以 http:// 或 https:// 开头。"
            return
        }
        guard !cleanKey.isEmpty || session.hasStoredAPIKey else {
            message = "请输入 Unraid API Key。"
            return
        }

        let endpointPath = enteredURL.path.isEmpty || enteredURL.path == "/"
            ? normalizedPath(graphQLPath)
            : normalizedPath(enteredURL.path)
        var origin = URLComponents(url: enteredURL, resolvingAgainstBaseURL: false)
        origin?.path = ""
        origin?.query = nil
        origin?.fragment = nil
        guard let baseURL = origin?.url else {
            message = "无法识别该服务器地址。"
            return
        }

        isConnecting = true
        message = nil
        defer { isConnecting = false }
        do {
            try await session.configure(
                .init(
                    id: session.currentConfiguration?.id ?? UUID(),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tower" : name,
                    baseURL: baseURL,
                    graphQLPath: endpointPath,
                    allowSelfSignedCertificate: allowSelfSigned
                ),
                apiKey: cleanKey.isEmpty ? nil : cleanKey
            )
            if !isOnboarding { dismiss() }
        } catch {
            message = friendlyMessage(for: error)
        }
    }

    private func normalizedPath(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        return clean.isEmpty ? "/graphql" : "/\(clean)"
    }

    private func loadCurrentConfiguration() {
        guard !hasLoadedConfiguration else { return }
        hasLoadedConfiguration = true
        guard let configuration = session.currentConfiguration else { return }
        name = configuration.name
        address = configuration.baseURL.absoluteString
        graphQLPath = configuration.graphQLPath
        allowSelfSigned = configuration.allowSelfSignedCertificate
    }

    private func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("unauthorized") || text.contains("401") {
            return "API Key 无效或权限不足，请在 Unraid API 设置中检查。"
        }
        if text.localizedCaseInsensitiveContains("certificate") {
            return "无法验证服务器 HTTPS 证书。仅在你确认使用自签证书时开启高级选项。"
        }
        if text.localizedCaseInsensitiveContains("timed out") {
            return "连接超时，请确认 iPhone 能访问该服务器地址。"
        }
        return text
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct ConnectionField: View {
    let title: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboardType)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
    }
}
