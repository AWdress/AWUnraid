import AMSMB2
import Foundation

struct SMBConfiguration: Codable, Equatable {
    var host: String
    var share: String
    var username: String
}

struct SMBFileItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date?
}

final class SMBFileService: @unchecked Sendable {
    private let manager: SMB2Manager
    private let share: String

    init(configuration: SMBConfiguration, password: String) throws {
        guard let url = URL(string: "smb://\(configuration.host)"),
              let manager = SMB2Manager(
                url: url,
                credential: URLCredential(user: configuration.username, password: password, persistence: .forSession)
              ) else { throw URLError(.badURL) }
        self.manager = manager
        self.share = configuration.share
    }

    func connect() async throws { try await manager.connectShare(name: share) }

    private func ensureConnected() async throws {
        try await manager.connectShare(name: share)
    }

    func list(path: String) async throws -> [SMBFileItem] {
        try await ensureConnected()
        let values = try await manager.contentsOfDirectory(atPath: path)
        return values.compactMap { attributes in
            guard let name = attributes[.nameKey] as? String, name != ".", name != ".." else { return nil }
            let itemPath = attributes[.pathKey] as? String ?? join(path, name)
            let type = attributes[.fileResourceTypeKey] as? URLFileResourceType
            return SMBFileItem(
                name: name,
                path: itemPath,
                isDirectory: type == .directory,
                size: (attributes[.fileSizeKey] as? NSNumber)?.int64Value ?? (attributes[.fileSizeKey] as? Int64) ?? 0,
                modifiedAt: attributes[.contentModificationDateKey] as? Date
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func createDirectory(path: String) async throws {
        try await ensureConnected()
        try await manager.createDirectory(atPath: path)
    }
    func remove(path: String) async throws {
        try await ensureConnected()
        try await manager.removeItem(atPath: path)
    }
    func move(from: String, to: String) async throws {
        try await ensureConnected()
        try await manager.moveItem(atPath: from, toPath: to)
    }
    func copy(from: String, to: String, recursive: Bool) async throws {
        try await ensureConnected()
        try await manager.copyItem(atPath: from, toPath: to, recursive: recursive, progress: { _, _ in true })
    }
    func upload(localURL: URL, to remotePath: String) async throws {
        try await ensureConnected()
        try await manager.uploadItem(at: localURL, toPath: remotePath, progress: { _ in true })
    }
    func download(path: String, fileName: String) async throws -> URL {
        try await ensureConnected()
        let directory = FileManager.default.temporaryDirectory.appending(path: "AW-Unraid-Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: fileName)
        try await manager.downloadItem(atPath: path, to: destination, progress: { _, _ in true })
        return destination
    }

    private func join(_ path: String, _ name: String) -> String {
        path == "/" || path.isEmpty ? "/\(name)" : "\(path)/\(name)"
    }
}

@MainActor
final class SMBFileStore: ObservableObject {
    @Published var configuration = SMBConfiguration(host: "", share: "", username: "guest")
    @Published var password = ""
    @Published var isConfigured = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var service: SMBFileService?
    private let configurationKey = "aw-unraid.smb-configuration"
    private let passwordAccount = "aw-unraid.smb-password"

    init() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(SMBConfiguration.self, from: data),
              let password = KeychainStore.load(account: passwordAccount) else { return }
        self.configuration = configuration
        self.password = password
        if let service = try? SMBFileService(configuration: configuration, password: password) {
            self.service = service
            isConfigured = true
        }
    }

    func configure() async throws {
        let clean = SMBConfiguration(
            host: configuration.host.trimmingCharacters(in: .whitespacesAndNewlines),
            share: configuration.share.trimmingCharacters(in: CharacterSet(charactersIn: " /")),
            username: configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !clean.host.isEmpty, !clean.share.isEmpty, !clean.username.isEmpty else { throw URLError(.badURL) }
        let proposed = try SMBFileService(configuration: clean, password: password)
        try await proposed.connect()
        try KeychainStore.save(password, account: passwordAccount)
        UserDefaults.standard.set(try JSONEncoder().encode(clean), forKey: configurationKey)
        configuration = clean
        service = proposed
        isConfigured = true
    }

    func disconnect() throws {
        try KeychainStore.delete(account: passwordAccount)
        UserDefaults.standard.removeObject(forKey: configurationKey)
        configuration = .init(host: "", share: "", username: "guest")
        password = ""
        service = nil
        isConfigured = false
    }

    func list(path: String) async throws -> [SMBFileItem] { try await requireService().list(path: path) }
    func createFolder(name: String, in path: String) async throws { try await requireService().createDirectory(path: join(path, name)) }
    func remove(_ item: SMBFileItem) async throws { try await requireService().remove(path: item.path) }
    func rename(_ item: SMBFileItem, to name: String, in path: String) async throws { try await requireService().move(from: item.path, to: join(path, name)) }
    func duplicate(_ item: SMBFileItem, in path: String) async throws {
        let base = (item.name as NSString).deletingPathExtension
        let ext = (item.name as NSString).pathExtension
        let copyName = ext.isEmpty ? "\(base) 副本" : "\(base) 副本.\(ext)"
        try await requireService().copy(from: item.path, to: join(path, copyName), recursive: item.isDirectory)
    }
    func upload(_ localURL: URL, in path: String) async throws { try await requireService().upload(localURL: localURL, to: join(path, localURL.lastPathComponent)) }
    func download(_ item: SMBFileItem) async throws -> URL { try await requireService().download(path: item.path, fileName: item.name) }

    private func requireService() throws -> SMBFileService {
        guard let service else { throw URLError(.userAuthenticationRequired) }
        return service
    }
    private func join(_ path: String, _ name: String) -> String { path == "/" || path.isEmpty ? "/\(name)" : "\(path)/\(name)" }
}
