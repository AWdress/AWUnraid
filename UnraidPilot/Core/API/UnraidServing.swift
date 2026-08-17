import Foundation

protocol UnraidServing {
    func fetchSnapshot() async throws -> ServerSnapshot
    func perform(_ action: ContainerAction, containerID: String) async throws
    func updateAllContainers() async throws
    func setContainerAutoStart(id: String, enabled: Bool, wait: Int?) async throws
    func removeContainer(id: String, withImage: Bool) async throws
    func perform(_ action: VirtualMachineAction, vmID: String) async throws
    func perform(_ action: ParityAction) async throws
    func perform(_ action: ArrayAction) async throws
    func fetchContainerLogs(id: String, tail: Int) async throws -> [String]
    func fetchNotifications() async throws -> [AppNotification]
    func fetchLogFiles() async throws -> [LogFileItem]
    func fetchLogFile(path: String) async throws -> String
}

struct MockUnraidClient: UnraidServing {
    func fetchSnapshot() async throws -> ServerSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        return .preview
    }
    func perform(_ action: ContainerAction, containerID: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func updateAllContainers() async throws { try await Task.sleep(for: .milliseconds(300)) }
    func setContainerAutoStart(id: String, enabled: Bool, wait: Int?) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func removeContainer(id: String, withImage: Bool) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func perform(_ action: VirtualMachineAction, vmID: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func perform(_ action: ParityAction) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func perform(_ action: ArrayAction) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func fetchContainerLogs(id: String, tail: Int) async throws -> [String] { ["AW Unraid Mock Log", "Container is running"] }
    func fetchNotifications() async throws -> [AppNotification] { [] }
    func fetchLogFiles() async throws -> [LogFileItem] { [] }
    func fetchLogFile(path: String) async throws -> String { "Mock log" }
}
