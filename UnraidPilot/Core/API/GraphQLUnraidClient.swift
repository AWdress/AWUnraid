import Foundation

enum UnraidAPIError: LocalizedError {
    case invalidResponse
    case server(Int)
    case graphQL([String])
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无效响应"
        case .server(let code): "服务器请求失败（HTTP \(code)）"
        case .graphQL(let messages): messages.joined(separator: "\n")
        case .unsupportedSchema: "当前插件的 GraphQL Schema 尚未适配，请导出 Schema 后再接入"
        }
    }
}

final class GraphQLUnraidClient: UnraidServing {
    private let configuration: ServerConfiguration
    private let apiKey: String
    private let session: URLSession

    init(configuration: ServerConfiguration, apiKey: String) {
        self.configuration = configuration
        self.apiKey = apiKey
        let delegate = ServerTrustDelegate(allowSelfSigned: configuration.allowSelfSignedCertificate)
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    func fetchSnapshot() async throws -> ServerSnapshot {
        let query = """
        query MobileDashboard {
          online
          vars { name sbState sbSyncErrs }
          info { os { hostname uptime } }
          metrics {
            cpu { percentTotal }
            memory { percentTotal }
            network { name operstate rxSec txSec }
          }
          array {
            state
            capacity { kilobytes { used total free } }
            parityCheckStatus { status errors running progress }
            disks { id name device size status temp fsSize fsUsed fsFree fsType numErrors }
          }
          docker {
            containers {
              id names image command created state status
              autoStart autoStartOrder autoStartWait
              iconUrl webUiUrl isOrphaned isUpdateAvailable
              sizeRootFs sizeRw sizeLog mounts
              hostConfig { networkMode }
              ports { ip privatePort publicPort type }
            }
          }
        }
        """
        let root = try await execute(query: query)
        guard let data = root.object("data") else { throw UnraidAPIError.unsupportedSchema }
        var snapshot = try decodeSnapshot(data)
        snapshot.virtualMachines = await fetchVirtualMachinesIfAvailable()
        return snapshot
    }

    private func fetchVirtualMachinesIfAvailable() async -> [VirtualMachineSnapshot] {
        let query = "query MobileVMs { vms { domains { id name state } } }"
        guard let root = try? await execute(query: query) else { return [] }
        return (root.object("data")?.object("vms")?.objects("domains") ?? []).map { raw in
            let rawState = (raw.string("state") ?? "").uppercased()
            let state: VirtualMachineSnapshot.State
            switch rawState {
            case "RUNNING", "IDLE": state = .running
            case "PAUSED", "PMSUSPENDED": state = .paused
            case "SHUTDOWN", "SHUTOFF": state = .stopped
            default: state = .unknown
            }
            return .init(
                id: raw.string("id") ?? UUID().uuidString,
                name: raw.string("name") ?? "VM",
                state: state
            )
        }
    }

    private func decodeSnapshot(_ data: [String: Any]) throws -> ServerSnapshot {
        let info = data.object("info")
        let os = info?.object("os")
        let vars = data.object("vars")
        let metrics = data.object("metrics")
        let array = data.object("array")
        let capacity = array?.object("capacity")?.object("kilobytes")

        let cpu = metrics?.object("cpu")?.double("percentTotal") ?? 0
        let memory = metrics?.object("memory")?.double("percentTotal") ?? 0
        let networkBytes = (metrics?.objects("network") ?? [])
            .filter { ($0.string("operstate") ?? "").lowercased() == "up" }
            .reduce(0.0) { $0 + $1.double("rxSec") + $1.double("txSec") }

        let disks = (array?.objects("disks") ?? []).map { raw -> DiskSnapshot in
            let temp = Int(raw.double("temp"))
            let warning = Int(raw.double("numErrors")) > 0 || temp >= 47
            let rawSize = raw.double("fsSize") > 0 ? raw.double("fsSize") : raw.double("size")
            return DiskSnapshot(
                id: raw.string("id") ?? raw.string("device") ?? UUID().uuidString,
                name: raw.string("name") ?? raw.string("device") ?? "Disk",
                model: [raw.string("device"), raw.string("fsType")].compactMap { $0 }.joined(separator: " · "),
                temperature: temp,
                totalTB: rawSize / 1_000_000_000_000,
                status: warning ? .warning : .healthy
            )
        }

        let containers = (data.object("docker")?.objects("containers") ?? []).map { raw -> ContainerSnapshot in
            let stateText = (raw.string("state") ?? "stopped").lowercased()
            let state: ContainerSnapshot.State = stateText == "running" ? .running : (stateText == "paused" ? .paused : .stopped)
            return ContainerSnapshot(
                id: raw.string("id") ?? UUID().uuidString,
                name: raw.strings("names").first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "Container",
                image: raw.string("image") ?? "",
                state: state,
                status: raw.string("status") ?? "",
                iconURL: raw.url("iconUrl"),
                webUIURL: raw.url("webUiUrl"),
                autoStart: raw.bool("autoStart") ?? false,
                autoStartOrder: raw.optionalInt("autoStartOrder"),
                autoStartWait: raw.optionalInt("autoStartWait"),
                updateAvailable: raw.bool("isUpdateAvailable") ?? false,
                isOrphaned: raw.bool("isOrphaned") ?? false,
                networkMode: raw.object("hostConfig")?.string("networkMode") ?? "—",
                command: raw.string("command") ?? "",
                created: Int(raw.double("created")),
                rootSize: Int64(raw.double("sizeRootFs")),
                writableSize: Int64(raw.double("sizeRw")),
                logSize: Int64(raw.double("sizeLog")),
                ports: raw.objects("ports").map {
                    .init(
                        ip: $0.string("ip"),
                        privatePort: $0.optionalInt("privatePort"),
                        publicPort: $0.optionalInt("publicPort"),
                        type: $0.string("type") ?? "TCP"
                    )
                },
                mounts: raw.objects("mounts").map {
                    .init(
                        source: $0.stringAnyCase("source") ?? "—",
                        destination: $0.stringAnyCase("destination") ?? "—",
                        type: $0.stringAnyCase("type") ?? "bind",
                        readOnly: $0.boolAnyCase("readOnly") ?? !($0.boolAnyCase("rw", default: true) ?? true)
                    )
                }
            )
        }

        let parity = array?.object("parityCheckStatus")
        let parityErrors = Int(parity?.double("errors") ?? 0)
        let warningCount = disks.filter { $0.status == .warning }.count
        let health = max(0, 100 - warningCount * 8 - min(parityErrors, 20))
        let usedKB = capacity?.double("used") ?? 0
        let totalKB = capacity?.double("total") ?? 0

        return ServerSnapshot(
            name: vars?.string("name") ?? os?.string("hostname") ?? configuration.name,
            address: configuration.baseURL.host ?? configuration.baseURL.absoluteString,
            isOnline: data.bool("online") ?? true,
            healthScore: health,
            uptime: Self.formatUptime(os?.string("uptime")),
            cpuUsage: Self.normalizedPercent(cpu),
            memoryUsage: Self.normalizedPercent(memory),
            networkRate: Self.formatRate(networkBytes),
            arrayUsedTB: usedKB / 1_000_000_000,
            arrayTotalTB: totalKB / 1_000_000_000,
            arrayStarted: (array?.string("state") ?? "").uppercased() == "STARTED",
            parityValid: parityErrors == 0,
            parityRunning: parity?.bool("running") ?? false,
            parityProgress: min(max((parity?.double("progress") ?? 0) / 100, 0), 1),
            disks: disks,
            containers: containers,
            virtualMachines: []
        )
    }

    func perform(_ action: ContainerAction, containerID: String) async throws {
        if action == .restart {
            try await perform(.stop, containerID: containerID)
            try await perform(.start, containerID: containerID)
            return
        }
        let field: String
        switch action {
        case .start: field = "start"
        case .stop: field = "stop"
        case .pause: field = "pause"
        case .resume: field = "unpause"
        case .update: field = "updateContainer"
        case .restart: return
        }
        let mutation = "mutation ContainerAction($id: PrefixedID!) { docker { \(field)(id: $id) { id state status } } }"
        _ = try await execute(query: mutation, variables: ["id": containerID])
    }

    func updateAllContainers() async throws {
        _ = try await execute(query: "mutation { docker { updateAllContainers { id state status isUpdateAvailable } } }")
    }

    func setContainerAutoStart(id: String, enabled: Bool, wait: Int?) async throws {
        var entry: [String: Any] = ["id": id, "autoStart": enabled]
        if let wait { entry["wait"] = wait }
        let mutation = "mutation AutoStart($entries: [DockerAutostartEntryInput!]!) { docker { updateAutostartConfiguration(entries: $entries, persistUserPreferences: true) } }"
        _ = try await execute(query: mutation, variables: ["entries": [entry]])
    }

    func removeContainer(id: String, withImage: Bool) async throws {
        let mutation = "mutation RemoveContainer($id: PrefixedID!, $withImage: Boolean) { docker { removeContainer(id: $id, withImage: $withImage) } }"
        _ = try await execute(query: mutation, variables: ["id": id, "withImage": withImage])
    }

    func perform(_ action: VirtualMachineAction, vmID: String) async throws {
        let field: String
        switch action {
        case .start: field = "start"
        case .stop: field = "stop"
        case .pause: field = "pause"
        case .resume: field = "resume"
        case .forceStop: field = "forceStop"
        case .reboot: field = "reboot"
        case .reset: field = "reset"
        }
        let mutation = "mutation VmAction($id: PrefixedID!) { vm { \(field)(id: $id) } }"
        _ = try await execute(query: mutation, variables: ["id": vmID])
    }

    func perform(_ action: ParityAction) async throws {
        let mutation: String
        let variables: [String: Any]
        switch action {
        case .start(let correcting):
            mutation = "mutation StartParity($correct: Boolean!) { parityCheck { start(correct: $correct) } }"
            variables = ["correct": correcting]
        case .pause:
            mutation = "mutation { parityCheck { pause } }"; variables = [:]
        case .resume:
            mutation = "mutation { parityCheck { resume } }"; variables = [:]
        case .cancel:
            mutation = "mutation { parityCheck { cancel } }"; variables = [:]
        }
        _ = try await execute(query: mutation, variables: variables)
    }

    func perform(_ action: ArrayAction) async throws {
        let desiredState = action == .start ? "START" : "STOP"
        let mutation = "mutation ArrayState($input: ArrayStateInput!) { array { setState(input: $input) { state } } }"
        _ = try await execute(query: mutation, variables: ["input": ["desiredState": desiredState]])
    }

    func fetchContainerLogs(id: String, tail: Int) async throws -> [String] {
        let query = "query ContainerLogs($id: PrefixedID!, $tail: Int) { docker { logs(id: $id, tail: $tail) { lines { timestamp message } cursor } } }"
        let root = try await execute(query: query, variables: ["id": id, "tail": tail])
        return (root.object("data")?.object("docker")?.object("logs")?.objects("lines") ?? []).map { line in
            let timestamp = line.string("timestamp") ?? ""
            let message = line.string("message") ?? ""
            return timestamp.isEmpty ? message : "[\(timestamp)] \(message)"
        }
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let query = "query { notifications { warningsAndAlerts { id title subject description importance timestamp formattedTimestamp } } }"
        let root = try await execute(query: query)
        return (root.object("data")?.object("notifications")?.objects("warningsAndAlerts") ?? []).map { raw in
            AppNotification(
                id: raw.string("id") ?? UUID().uuidString,
                title: raw.string("title") ?? raw.string("subject") ?? "通知",
                detail: raw.string("description") ?? "",
                importance: raw.string("importance") ?? "INFO",
                timestamp: raw.string("formattedTimestamp") ?? raw.string("timestamp") ?? ""
            )
        }
    }

    func fetchLogFiles() async throws -> [LogFileItem] {
        let query = "query { logFiles { name path size modifiedAt } }"
        let root = try await execute(query: query)
        return (root.object("data")?.objects("logFiles") ?? []).map { raw in
            LogFileItem(name: raw.string("name") ?? "Log", path: raw.string("path") ?? "", size: Int(raw.double("size")), modifiedAt: raw.string("modifiedAt") ?? "")
        }
    }

    func fetchLogFile(path: String) async throws -> String {
        let query = "query LogContent($path: String!) { logFile(path: $path) { content totalLines } }"
        let root = try await execute(query: query, variables: ["path": path])
        return root.object("data")?.object("logFile")?.string("content") ?? ""
    }

    private static func normalizedPercent(_ value: Double) -> Double {
        min(max(value > 1 ? value / 100 : value, 0), 1)
    }

    private static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        if bytesPerSecond >= 1_000 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    private static func formatUptime(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let seconds: TimeInterval
        if let numeric = Double(raw) {
            seconds = numeric
        } else if let bootDate = ISO8601DateFormatter().date(from: raw) {
            seconds = max(Date().timeIntervalSince(bootDate), 0)
        } else {
            return "—"
        }
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 { return "\(days)天 \(hours)小时" }
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours)小时 \(minutes)分钟"
    }

    func execute(query: String, variables: [String: Any] = [:]) async throws -> [String: Any] {
        let endpoint = configuration.baseURL.appending(path: configuration.graphQLPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UnraidAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw UnraidAPIError.server(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UnraidAPIError.invalidResponse }
        if let errors = json["errors"] as? [[String: Any]] {
            throw UnraidAPIError.graphQL(errors.compactMap { $0["message"] as? String })
        }
        return json
    }
}

private extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func objects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func strings(_ key: String) -> [String] { self[key] as? [String] ?? [] }
    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return nil
    }
    func double(_ key: String) -> Double {
        if let value = self[key] as? NSNumber { return value.doubleValue }
        if let value = self[key] as? String { return Double(value) ?? 0 }
        return 0
    }
    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }
    func optionalInt(_ key: String) -> Int? {
        if self[key] is NSNull || self[key] == nil { return nil }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }
    func url(_ key: String) -> URL? {
        guard let value = string(key), !value.isEmpty else { return nil }
        return URL(string: value)
    }
    func stringAnyCase(_ key: String) -> String? {
        let match = first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        if let value = match?.value as? String { return value }
        return nil
    }
    func boolAnyCase(_ key: String, default fallback: Bool? = nil) -> Bool? {
        let match = first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        if let value = match?.value as? Bool { return value }
        if let value = match?.value as? NSNumber { return value.boolValue }
        return fallback
    }
}

private final class ServerTrustDelegate: NSObject, URLSessionDelegate {
    let allowSelfSigned: Bool
    init(allowSelfSigned: Bool) { self.allowSelfSigned = allowSelfSigned }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard allowSelfSigned,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
