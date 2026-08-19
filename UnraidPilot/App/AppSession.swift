import Foundation

@MainActor
final class AppSession: ObservableObject {
    @Published var selectedTab: AppTab = .overview
    @Published var server: ServerSnapshot = .preview
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var operationMessage: String?
    @Published var isConfigured = false

    private var client: UnraidServing = MockUnraidClient()
    private let configurationKey = "aw-unraid.server-configuration"
    private var configuration: ServerConfiguration?

    var serverHost: String { configuration?.baseURL.host ?? "" }

    init() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(ServerConfiguration.self, from: data),
              let apiKey = KeychainStore.load(account: configuration.id.uuidString) else { return }
        client = GraphQLUnraidClient(configuration: configuration, apiKey: apiKey)
        self.configuration = configuration
        isConfigured = true
    }

    func configure(_ configuration: ServerConfiguration, apiKey: String) async throws {
        let proposedClient = GraphQLUnraidClient(configuration: configuration, apiKey: apiKey)
        let proposedSnapshot = try await proposedClient.fetchSnapshot()
        try KeychainStore.save(apiKey, account: configuration.id.uuidString)
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: configurationKey)
        }
        client = proposedClient
        self.configuration = configuration
        server = proposedSnapshot
        isConfigured = true
    }

    func disconnect() throws {
        if let configuration {
            try KeychainStore.delete(account: configuration.id.uuidString)
        }
        UserDefaults.standard.removeObject(forKey: configurationKey)
        self.configuration = nil
        client = MockUnraidClient()
        server = .preview
        errorMessage = nil
        operationMessage = nil
        isConfigured = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            server = try await client.fetchSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perform(_ action: ContainerAction, containerID: String) async {
        await runOperation { try await client.perform(action, containerID: containerID) }
    }

    func updateAllContainers() async {
        await runOperation { try await client.updateAllContainers() }
    }

    func setContainerAutoStart(id: String, enabled: Bool, wait: Int?) async {
        await runOperation { try await client.setContainerAutoStart(id: id, enabled: enabled, wait: wait) }
    }

    func removeContainer(id: String, withImage: Bool) async {
        await runOperation { try await client.removeContainer(id: id, withImage: withImage) }
    }

    func perform(_ action: VirtualMachineAction, vmID: String) async {
        await runOperation { try await client.perform(action, vmID: vmID) }
    }

    func perform(_ action: ParityAction) async {
        await runOperation { try await client.perform(action) }
    }

    func perform(_ action: ArrayAction) async {
        await runOperation { try await client.perform(action) }
    }

    func containerLogs(id: String, tail: Int = 300) async throws -> [String] {
        try await client.fetchContainerLogs(id: id, tail: tail)
    }

    func notifications() async throws -> [AppNotification] { try await client.fetchNotifications() }
    func logFiles() async throws -> [LogFileItem] { try await client.fetchLogFiles() }
    func logFile(path: String) async throws -> String { try await client.fetchLogFile(path: path) }

    private func runOperation(_ operation: () async throws -> Void) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await operation()
            operationMessage = "操作已完成"
            server = try await client.fetchSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AppTab: Hashable {
    case overview, storage, containers, files, more
}
