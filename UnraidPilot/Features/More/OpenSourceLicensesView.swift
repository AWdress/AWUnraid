import SwiftUI

struct OpenSourceLicensesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AMSMB2")
                        .font(.headline)
                    Text("版本 4.0.3 · GNU Lesser General Public License 2.1")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("AW Unraid 通过动态框架使用 AMSMB2，实现原生 SMB2/3 文件访问。")
                        .font(.subheadline)
                    Link("查看项目与完整许可", destination: URL(string: "https://github.com/amosavian/AMSMB2")!)
                }
                .padding(.vertical, 6)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
