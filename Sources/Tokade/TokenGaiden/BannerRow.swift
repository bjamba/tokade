import SwiftUI

/// A coloured-stripe alert row used by the Token Gaiden tab to surface
/// urgent state (low HP, critical, near-death). Lives at the top of the
/// alive layout when any of those conditions are active.
struct BannerRow: View {
    let color: Color
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(.title2, design: .monospaced))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).gameFont(.body).fontWeight(.semibold)
                Text(detail).gameFont(.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(color)
                .frame(width: 4),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
