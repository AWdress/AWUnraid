import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Tower"
    var isOnboarding = false
    @State private var address = "http://192.168.50.113"
    @State private var graphQLPath = "/graphql"
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("服务器") {
                TextField("名称", text: $name)
                TextField("地址", text: $address).textInputAutocapitalization(.never).keyboardType(.URL)
                TextField("GraphQL 路径", text: $graphQLPath).textInputAutocapitalization(.never)
            }
            Section("认证") { SecureField("API Key", text: $apiKey); Toggle("允许已确认的自签证书", isOn: $allowSelfSigned) }
            Section { Button("保存并连接") { Task { await save() } }.frame(maxWidth: .infinity) }
            if let message { Section { Text(message).foregroundStyle(AppTheme.warning) } }
        }.navigationTitle(isOnboarding ? "连接 AW Unraid" : "连接设置").navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        guard let url = URL(string: address), !apiKey.isEmpty else { message = "请填写有效地址和 API Key"; return }
        do {
            try await session.configure(.init(name: name, baseURL: url, graphQLPath: graphQLPath, allowSelfSignedCertificate: allowSelfSigned), apiKey: apiKey)
            if !isOnboarding { dismiss() }
        } catch { message = error.localizedDescription }
    }
}
