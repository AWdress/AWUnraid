import Foundation

struct RemoteFileItem: Identifiable, Equatable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date?
}

final class RemoteFileService: @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession
    private let candidates: [URL]
    private var selectedBaseURL: URL?

    init(configuration: ServerConfiguration, apiKey: String) {
        self.apiKey = apiKey
        self.session = URLSession(configuration: .ephemeral, delegate: ServerTrustDelegate(allowSelfSigned: configuration.allowSelfSignedCertificate), delegateQueue: nil)
        var values = [configuration.baseURL.appending(path: "aw-files")]
        if var local = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) {
            local.port = 8089
            local.path = ""
            if let url = local.url, !values.contains(url) { values.append(url) }
        }
        candidates = values
    }

    func connect() async throws {
        var lastError: Error = URLError(.cannotConnectToHost)
        for candidate in candidates {
            do {
                var request = authenticatedRequest(url: candidate.appending(path: "health")); request.httpMethod = "GET"
                let (_, response) = try await session.data(for: request)
                try validate(response); selectedBaseURL = candidate; return
            } catch { lastError = error }
        }
        throw lastError
    }

    func list(path: String) async throws -> [RemoteFileItem] {
        let data = try await request(method: "GET", endpoint: "files", query: ["path": path])
        return try JSONDecoder.awFiles.decode([RemoteFileItem].self, from: data)
    }
    func createDirectory(path: String) async throws { _ = try await request(method: "POST", endpoint: "directories", json: ["path": path]) }
    func remove(path: String) async throws { _ = try await request(method: "DELETE", endpoint: "files", query: ["path": path]) }
    func move(from: String, to: String) async throws { _ = try await request(method: "POST", endpoint: "move", json: ["source": from, "destination": to]) }
    func copy(from: String, to: String, recursive: Bool) async throws { _ = try await request(method: "POST", endpoint: "copy", json: ["source": from, "destination": to]) }
    func upload(localURL: URL, to remotePath: String) async throws {
        let request = try await makeRequest(method: "PUT", endpoint: "files", query: ["path": remotePath], contentType: "application/octet-stream")
        let (_, response) = try await session.upload(for: request, fromFile: localURL)
        try validate(response)
    }
    func download(path: String, fileName: String) async throws -> URL {
        let request = try await makeRequest(method: "GET", endpoint: "download", query: ["path": path])
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response)
        let directory = FileManager.default.temporaryDirectory.appending(path: "AW-Unraid-Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func request(method: String, endpoint: String, query: [String: String] = [:], json: [String: String]? = nil, body: Data? = nil, contentType: String? = nil) async throws -> Data {
        var request = try await makeRequest(method: method, endpoint: endpoint, query: query, contentType: contentType)
        if let json { request.httpBody = try JSONEncoder().encode(json); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        else { request.httpBody = body }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }
    private func makeRequest(method: String, endpoint: String, query: [String: String], contentType: String? = nil) async throws -> URLRequest {
        if selectedBaseURL == nil { try await connect() }
        guard let baseURL = selectedBaseURL else { throw URLError(.cannotConnectToHost) }
        var components = URLComponents(url: baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = authenticatedRequest(url: url); request.httpMethod = method
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url); request.timeoutInterval = 20; request.setValue(apiKey, forHTTPHeaderField: "x-api-key"); return request
    }
    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw UnraidAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw UnraidAPIError.server(response.statusCode) }
    }
}

@MainActor
final class RemoteFileStore: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var errorMessage: String?
    private let service: RemoteFileService
    init(configuration: ServerConfiguration, apiKey: String) { service = RemoteFileService(configuration: configuration, apiKey: apiKey) }
    func connect() async {
        guard !isConnecting else { return }; isConnecting = true; defer { isConnecting = false }
        do { try await service.connect(); isConnected = true; errorMessage = nil }
        catch { isConnected = false; errorMessage = error.localizedDescription }
    }
    func list(path: String) async throws -> [RemoteFileItem] {
        let items = try await service.list(path: path)
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func createFolder(name: String, in path: String) async throws { try await service.createDirectory(path: join(path, name)) }
    func remove(_ item: RemoteFileItem) async throws { try await service.remove(path: item.path) }
    func rename(_ item: RemoteFileItem, to name: String, in path: String) async throws { try await service.move(from: item.path, to: join(path, name)) }
    func duplicate(_ item: RemoteFileItem, in path: String) async throws {
        let base = (item.name as NSString).deletingPathExtension, ext = (item.name as NSString).pathExtension
        try await service.copy(from: item.path, to: join(path, ext.isEmpty ? "\(base) 副本" : "\(base) 副本.\(ext)"), recursive: item.isDirectory)
    }
    func upload(_ localURL: URL, in path: String) async throws { try await service.upload(localURL: localURL, to: join(path, localURL.lastPathComponent)) }
    func download(_ item: RemoteFileItem) async throws -> URL { try await service.download(path: item.path, fileName: item.name) }
    private func join(_ path: String, _ name: String) -> String { path == "/" || path.isEmpty ? "/\(name)" : "\(path)/\(name)" }
}

private extension JSONDecoder {
    static var awFiles: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date"))
        }
        return value
    }
}
