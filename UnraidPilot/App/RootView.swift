import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if session.isConfigured {
                TabView(selection: $session.selectedTab) {
                    NavigationStack { DashboardView() }
                        .tabItem { Label("总览", systemImage: "square.grid.2x2.fill") }
                        .tag(AppTab.overview)
                    NavigationStack { StorageView() }
                        .tabItem { Label("存储", systemImage: "externaldrive.fill") }
                        .tag(AppTab.storage)
                    NavigationStack { ContainersView() }
                        .tabItem { Label("容器", systemImage: "shippingbox.fill") }
                        .tag(AppTab.containers)
                    NavigationStack { FileManagerRootView() }
                        .tabItem { Label("文件", systemImage: "folder.fill") }
                        .tag(AppTab.files)
                    NavigationStack { MoreView() }
                        .tabItem { Label("更多", systemImage: "ellipsis") }
                        .tag(AppTab.more)
                }
                .tint(AppTheme.accent)
                .task { await session.refresh() }
            } else {
                NavigationStack { ServerSettingsView(isOnboarding: true) }
            }
        }
        .overlay(alignment: .top) {
            if session.isRefreshing && session.isConfigured {
                ProgressView("正在与 Unraid 通信…")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("好") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "未知错误")
        }
        .alert("AW Unraid", isPresented: Binding(
            get: { session.operationMessage != nil },
            set: { if !$0 { session.operationMessage = nil } }
        )) {
            Button("好") { session.operationMessage = nil }
        } message: {
            Text(session.operationMessage ?? "操作已完成")
        }
    }
}
