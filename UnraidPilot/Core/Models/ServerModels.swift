import Foundation

struct ServerConfiguration: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: URL
    var graphQLPath = "/graphql"
    var allowSelfSignedCertificate = false
}

struct ServerSnapshot: Equatable {
    var name: String
    var address: String
    var isOnline: Bool
    var healthScore: Int
    var uptime: String
    var cpuUsage: Double
    var memoryUsage: Double
    var networkRate: String
    var arrayUsedTB: Double
    var arrayTotalTB: Double
    var arrayStarted: Bool
    var parityValid: Bool
    var parityRunning: Bool
    var parityProgress: Double
    var disks: [DiskSnapshot]
    var containers: [ContainerSnapshot]
    var virtualMachines: [VirtualMachineSnapshot]
    var vmCount: Int { virtualMachines.count }

    static let preview = ServerSnapshot(
        name: "Tower", address: "192.168.1.100", isOnline: true,
        healthScore: 96, uptime: "12天 06:22", cpuUsage: 0.34,
        memoryUsage: 0.58, networkRate: "18 MB/s", arrayUsedTB: 8.72,
        arrayTotalTB: 16.34, arrayStarted: true, parityValid: true,
        parityRunning: false, parityProgress: 0,
        disks: [
            .init(id: "disk1", name: "Disk 1", model: "ST4000VN008", temperature: 32, totalTB: 3.64, status: .healthy),
            .init(id: "disk2", name: "Disk 2", model: "ST4000VN008", temperature: 31, totalTB: 3.64, status: .healthy),
            .init(id: "disk3", name: "Disk 3", model: "ST4000VN008", temperature: 33, totalTB: 3.64, status: .healthy),
            .init(id: "disk4", name: "Disk 4", model: "ST4000VN008", temperature: 48, totalTB: 3.64, status: .warning)
        ],
        containers: [
            .init(id: "plex", name: "Plex", image: "plexinc/pms-docker", state: .running),
            .init(id: "qb", name: "qBittorrent", image: "linuxserver/qbittorrent", state: .running),
            .init(id: "immich", name: "Immich", image: "ghcr.io/immich-app", state: .stopped)
        ], virtualMachines: [
            .init(id: "vm-windows", name: "Windows 11", state: .running),
            .init(id: "vm-ubuntu", name: "Ubuntu", state: .stopped)
        ]
    )
}

struct DiskSnapshot: Identifiable, Equatable {
    enum Status: String { case healthy, warning, offline }
    let id: String
    let name: String
    let model: String
    let temperature: Int
    let totalTB: Double
    let status: Status
}

struct ContainerSnapshot: Identifiable, Equatable {
    enum State: String { case running, paused, stopped }
    let id: String
    let name: String
    let image: String
    var state: State
    var status = ""
    var iconURL: URL?
    var webUIURL: URL?
    var autoStart = false
    var autoStartOrder: Int?
    var autoStartWait: Int?
    var updateAvailable = false
    var isOrphaned = false
    var networkMode = "—"
    var command = ""
    var created: Int = 0
    var rootSize: Int64 = 0
    var writableSize: Int64 = 0
    var logSize: Int64 = 0
    var ports: [ContainerPortSnapshot] = []
    var mounts: [ContainerMountSnapshot] = []
}

struct ContainerPortSnapshot: Identifiable, Equatable {
    var id: String { "\(ip ?? "*")-\(publicPort ?? 0)-\(privatePort ?? 0)-\(type)" }
    let ip: String?
    let privatePort: Int?
    let publicPort: Int?
    let type: String
}

struct ContainerMountSnapshot: Identifiable, Equatable {
    var id: String { "\(source)-\(destination)" }
    let source: String
    let destination: String
    let type: String
    let readOnly: Bool
}

struct VirtualMachineSnapshot: Identifiable, Equatable {
    enum State: String { case running, paused, stopped, unknown }
    let id: String
    let name: String
    var state: State
}

enum ContainerAction: Equatable { case start, stop, pause, resume, restart, update }
enum VirtualMachineAction: Equatable { case start, stop, pause, resume, forceStop, reboot, reset }
enum ParityAction: Equatable { case start(correcting: Bool), pause, resume, cancel }
enum ArrayAction: Equatable { case start, stop }

struct AppNotification: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let importance: String
    let timestamp: String
}

struct LogFileItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int
    let modifiedAt: String
}
