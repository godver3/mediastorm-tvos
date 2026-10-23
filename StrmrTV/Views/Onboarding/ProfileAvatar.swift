import SwiftUI

/// Round profile image: the server icon when there is one, otherwise the initial on
/// the profile colour (or a stable colour derived from the ID).
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            if let url = APIClient.shared.iconURL(for: profile) {
                // The initial shows only if the icon fails, never while it loads.
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): image.resizable().aspectRatio(contentMode: .fill)
                    case .failure: initialText
                    default: Color.clear
                    }
                }
            } else {
                initialText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialText: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
    }

    private var initial: String {
        profile.name.first.map { String($0).uppercased() } ?? "?"
    }

    private var color: Color {
        if let hex = profile.color, let c = Color(hex: hex) { return c }
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let sum = profile.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

extension Color {
    /// `#RRGGBB` or `RRGGBB`.
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
