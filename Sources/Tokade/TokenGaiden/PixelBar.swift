import SwiftUI

/// Segmented pixel-art progress bar. Used for HP / SP / age / quest progress
/// so the UI keeps a consistent retro look instead of mixing native
/// ProgressViews with the pixel-art sprites.
struct PixelBar: View {
    let value: Int
    let max: Int
    var color: Color = .red
    var width: CGFloat = 140
    var height: CGFloat = 10
    /// Number of segments. 10 reads as "tenths"; 20 reads as "twentieths".
    var segments: Int = 10

    var body: some View {
        let clamped = Swift.max(0, Swift.min(value, max))
        let fillRatio = max > 0 ? Double(clamped) / Double(max) : 0
        let filledSegments = Int((fillRatio * Double(segments)).rounded())
        let segWidth = (width - CGFloat(segments + 1)) / CGFloat(segments)
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Frame
                Rectangle()
                    .fill(Color.black)
                // Inner background (dark grey)
                Rectangle()
                    .fill(Color(white: 0.15))
                    .padding(1)
                // Filled segments
                HStack(spacing: 1) {
                    ForEach(0..<segments, id: \.self) { i in
                        Rectangle()
                            .fill(i < filledSegments ? color : Color.clear)
                            .frame(width: segWidth, height: height - 4)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(width: width, height: height)
        }
    }
}

/// Consistent palette for in-game bars and chat-log frames.
enum GamePalette {
    static let hp = Color(red: 0.85, green: 0.18, blue: 0.20)
    static let sp = Color(red: 0.25, green: 0.55, blue: 0.95)
    static let age = Color(red: 0.75, green: 0.55, blue: 0.95)
    static let exp = Color(red: 0.95, green: 0.80, blue: 0.20)
    static let frameOutline = Color.black
    static let frameInnerLight = Color(red: 0.92, green: 0.87, blue: 0.75)
    static let frameInnerDark = Color(red: 0.18, green: 0.18, blue: 0.22)
}

/// 8/16-bit style framed text box. Used for battle logs and dialog so they
/// look consistent and don't grow responsively.
struct PixelTextFrame<Content: View>: View {
    let height: CGFloat
    let content: () -> Content

    init(height: CGFloat = 80, @ViewBuilder content: @escaping () -> Content) {
        self.height = height
        self.content = content
    }

    var body: some View {
        ZStack {
            Rectangle().fill(GamePalette.frameInnerDark)
            Rectangle()
                .stroke(GamePalette.frameOutline, lineWidth: 2)
            Rectangle()
                .stroke(Color(white: 0.4), lineWidth: 1)
                .padding(2)
            VStack(alignment: .leading, spacing: 1) {
                content()
            }
            .padding(8)
        }
        .frame(height: height)
    }
}
