import SwiftUI

struct ContainerIconView: View {
    let container: ContainerSnapshot
    var size: CGFloat = 46

    var body: some View {
        AsyncImage(url: container.iconURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .accessibilityHidden(true)
    }
}
