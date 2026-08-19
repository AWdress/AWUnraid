import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct SMBDirectoryView: View {
    @ObservedObject var store: SMBFileStore
    let path: String
    let title: String

    @State private var items: [SMBFileItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var createsFolder = false
    @State private var folderName = ""
    @State private var importsFile = false
    @State private var renamingItem: SMBFileItem?
    @State private var newName = ""
    @State private var deletingItem: SMBFileItem?
    @State private var preview: LocalPreview?
    @State private var error: String?

    private var visibleItems: [SMBFileItem] {
        searchText.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("正在读取文件…")
            } else if items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                    Text("文件夹为空").font(.headline)
                    Text("可从右上角新建文件夹或上传文件。").font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(24)
            } else {
                List(visibleItems) { item in
                    if item.isDirectory {
                        NavigationLink {
                            SMBDirectoryView(store: store, path: item.path, title: item.name)
                        } label: { FileRow(item: item) }
                        .contextMenu { itemMenu(item) }
                    } else {
                        Button { Task { await open(item) } } label: { FileRow(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu { itemMenu(item) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索此文件夹")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("上传文件", systemImage: "square.and.arrow.up") { importsFile = true }
                    Button("新建文件夹", systemImage: "folder.badge.plus") { folderName = ""; createsFolder = true }
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await load() } }
                } label: { Image(systemName: "plus.circle") }
            }
        }
        .task { await load() }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let failure) = result { error = failure.localizedDescription }
                return
            }
            Task { await upload(url) }
        }
        .alert("新建文件夹", isPresented: $createsFolder) {
            TextField("文件夹名称", text: $folderName)
            Button("创建") { Task { await createFolder() } }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
            TextField("新名称", text: $newName)
            Button("保存") { Task { await renameSelected() } }
            Button("取消", role: .cancel) { renamingItem = nil }
        }
        .confirmationDialog("删除 \(deletingItem?.name ?? "项目")？", isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { Task { await deleteSelected() } }
            Button("取消", role: .cancel) { deletingItem = nil }
        } message: { Text("文件夹及其中内容会被递归删除，此操作无法撤销。") }
        .sheet(item: $preview) { QuickLookPreview(url: $0.url) }
        .alert("文件操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func itemMenu(_ item: SMBFileItem) -> some View {
        if !item.isDirectory { Button("下载并预览", systemImage: "arrow.down.circle") { Task { await open(item) } } }
        Button("重命名", systemImage: "pencil") { newName = item.name; renamingItem = item }
        Button("创建副本", systemImage: "doc.on.doc") { Task { await duplicate(item) } }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { deletingItem = item }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { items = try await store.list(path: path); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func createFolder() async {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { error = "文件夹名称不能为空或包含 /。"; return }
        do { try await store.createFolder(name: name, in: path); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func renameSelected() async {
        guard let item = renamingItem else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingItem = nil
        guard !name.isEmpty, !name.contains("/") else { error = "名称不能为空或包含 /。"; return }
        do { try await store.rename(item, to: name, in: path); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func deleteSelected() async {
        guard let item = deletingItem else { return }
        deletingItem = nil
        do { try await store.remove(item); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func duplicate(_ item: SMBFileItem) async {
        do { try await store.duplicate(item, in: path); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func upload(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try await store.upload(url, in: path); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func open(_ item: SMBFileItem) async {
        do { preview = LocalPreview(url: try await store.download(item)) }
        catch { self.error = error.localizedDescription }
    }
}

private struct FileRow: View {
    let item: SMBFileItem
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                .font(.body).foregroundStyle(item.isDirectory ? AppTheme.accent : .secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).foregroundStyle(.primary).lineLimit(1)
                if !item.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let date = item.modifiedAt { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(minHeight: 46)
    }

    private func fileIcon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif": return "photo.fill"
        case "mp4", "mkv", "mov": return "film.fill"
        case "mp3", "flac", "m4a": return "waveform"
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}

private struct LocalPreview: Identifiable { let id = UUID(); let url: URL }

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
