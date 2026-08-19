import SwiftUI

struct OpenSourceLicensesView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("第三方运行库")
                        .font(.headline)
                    Text("当前版本未包含第三方运行库")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
