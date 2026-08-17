import SwiftUI

struct ContainerLogsView: View {
    @EnvironmentObject private var session: AppSession
    let container: ContainerSnapshot
    @State private var lines: [String] = []
    @State private var error: String?
    @State private var isLoading = false
    @State private var query = ""
    @State private var tail = 300

    private var visibleLines: [String] {
        query.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lines.isEmpty && isLoading {
                Spacer(); ProgressView("正在读取日志…"); Spacer()
            } else if lines.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.secondary)
                    Text("暂无日志").font(.headline)
                    Button("重新读取") { Task { await load() } }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .onChange(of: lines.count) { _ in
                        if let last = visibleLines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("\(container.name) 日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "筛选日志")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("读取行数", selection: $tail) {
                        Text("最近 100 行").tag(100)
                        Text("最近 300 行").tag(300)
                        Text("最近 1,000 行").tag(1_000)
                        Text("最近 5,000 行").tag(5_000)
                    }
                    Button("重新读取", systemImage: "arrow.clockwise") { Task { await load() } }
                } label: { Image(systemName: "ellipsis.circle") }
                ShareLink(item: visibleLines.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task { await load() }
        .onChange(of: tail) { _ in Task { await load() } }
        .alert("日志读取失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("重试") { Task { await load() } }
            Button("取消", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do { lines = try await session.containerLogs(id: container.id, tail: tail); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
