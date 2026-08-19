import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                HealthPanel(snapshot: session.server)
                StoragePanel(snapshot: session.server)
                RunningPanel(snapshot: session.server)
                if let disk = session.server.disks.first(where: { $0.status == .warning }) {
                    WarningRow(disk: disk)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .refreshable { await session.refresh() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.server.name).font(.title.bold())
                HStack(spacing: 8) {
                    Circle().fill(session.server.isOnline ? AppTheme.healthy : AppTheme.warning).frame(width: 9, height: 9)
                    Text(session.server.isOnline ? "在线" : "离线").foregroundStyle(AppTheme.healthy)
                    Text("·  \(session.server.address)").foregroundStyle(AppTheme.secondaryText)
                }.font(.subheadline)
            }
            Spacer()
            NavigationLink(destination: ServerSettingsView()) {
                Image(systemName: "gearshape.fill").font(.title3).frame(width: 44, height: 44).background(AppTheme.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 13))
            }.foregroundStyle(.white)
        }.padding(.top, 8)
    }
}

private struct HealthPanel: View {
    let snapshot: ServerSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("系统健康").font(.headline)
                Label("良好 · \(snapshot.healthScore)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.healthy)
                Spacer()
                Text(snapshot.uptime).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            HStack(spacing: 0) {
                MetricColumn(title: "CPU", value: "\(Int(snapshot.cpuUsage * 100))%", points: [2,5,3,7,4,6,10,4])
                Divider().overlay(AppTheme.divider).padding(.horizontal, 10)
                MetricColumn(title: "内存", value: "\(Int(snapshot.memoryUsage * 100))%", points: [3,6,5,9,7,8,6,9])
                Divider().overlay(AppTheme.divider).padding(.horizontal, 10)
                MetricColumn(title: "网络", value: snapshot.networkRate, points: [2,3,7,4,9,5,7,6])
            }
        }.padding(14).appSurface()
    }
}

private struct MetricColumn: View {
    let title: String; let value: String; let points: [CGFloat]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
            Sparkline(points: points).stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(height: 22)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Sparkline: Shape {
    let points: [CGFloat]
    func path(in rect: CGRect) -> Path {
        var path = Path(); guard let max = points.max(), max > 0, points.count > 1 else { return path }
        for (index, point) in points.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(points.count - 1)
            let y = rect.height - rect.height * point / max
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }; return path
    }
}

private struct StoragePanel: View {
    let snapshot: ServerSnapshot
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("阵列与存储").font(.headline); Spacer(); Text(snapshot.parityValid ? "Parity 有效" : "需要校验").font(.subheadline).foregroundStyle(snapshot.parityValid ? AppTheme.healthy : AppTheme.warning) }.padding(14)
            VStack(spacing: 8) {
                HStack { Label("阵列", systemImage: "externaldrive.fill"); Spacer(); Text(String(format: "%.2f / %.2f TB", snapshot.arrayUsedTB, snapshot.arrayTotalTB)).foregroundStyle(AppTheme.secondaryText) }
                ProgressView(value: snapshot.arrayUsedTB, total: snapshot.arrayTotalTB).tint(AppTheme.accent)
            }.padding(.horizontal, 14).padding(.bottom, 10)
            ForEach(snapshot.disks) { disk in
                Divider().overlay(AppTheme.divider).padding(.leading, 16)
                DiskRow(disk: disk).padding(.horizontal, 14)
            }
        }.appSurface()
    }
}

private struct DiskRow: View {
    let disk: DiskSnapshot
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive.fill").font(.body).foregroundStyle(disk.status == .warning ? AppTheme.warning : AppTheme.secondaryText)
            VStack(alignment: .leading, spacing: 4) { Text(disk.name).font(.headline); Text(disk.model).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) { Text(String(format: "%.2f TB", disk.totalTB)); Text("\(disk.temperature)°C").foregroundStyle(disk.status == .warning ? AppTheme.warning : AppTheme.secondaryText) }
            Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
        }.padding(.vertical, 10)
    }
}

private struct RunningPanel: View {
    let snapshot: ServerSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("正在运行").font(.headline).padding(14)
            NavigationLink { ContainersView() } label: { ServiceRow(icon: "shippingbox.fill", title: "Docker", subtitle: "\(snapshot.containers.filter { $0.state == .running }.count) 个容器") }
            Divider().overlay(AppTheme.divider).padding(.leading, 60)
            ServiceRow(icon: "desktopcomputer", title: "虚拟机", subtitle: "\(snapshot.vmCount) 台虚拟机")
        }.foregroundStyle(.white).appSurface()
    }
}

private struct ServiceRow: View {
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(AppTheme.accent).frame(width: 28)
            VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            Spacer(); Circle().fill(AppTheme.healthy).frame(width: 8, height: 8); Text("运行中").font(.caption).foregroundStyle(AppTheme.secondaryText); Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
        }.padding(.horizontal, 14).frame(minHeight: 52)
    }
}

private struct WarningRow: View {
    let disk: DiskSnapshot
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.warning).font(.title2)
            VStack(alignment: .leading) { Text("\(disk.name) 温度过高").font(.headline); Text("当前温度 \(disk.temperature)°C，建议检查散热情况").font(.caption).foregroundStyle(AppTheme.secondaryText) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
        }.padding(14).background(AppTheme.warning.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.warning.opacity(0.18)))
    }
}
