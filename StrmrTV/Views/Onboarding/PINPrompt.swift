import SwiftUI

/// Outcome of checking an entered PIN.
enum PINVerification {
    case unlocked
    case wrong
    /// Rate limited, network, etc.: the message is shown and the entry kept for a retry.
    case failed(String)
}

/// Full-screen PIN entry for a protected profile: header and PIN dots beside a focusable number pad.
///
/// Fixed-length PINs (the server reports `pinLength`) submit on the last digit; otherwise
/// an OK button submits once the minimum length is reached. A wrong PIN shakes the dots
/// and clears them. Menu (or Cancel) backs out.
struct PINEntryView: View {
    let profile: Profile
    var notice: String?
    let verify: (String) async -> PINVerification
    let onCancel: () -> Void

    static let minLength = 4
    static let maxLength = 16

    @State private var digits = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isVerifying = false
    @State private var shakes = 0
    @FocusState private var focusedKey: PadKey?

    private var fixedLength: Int? {
        guard let n = profile.pinLength, n >= Self.minLength else { return nil }
        return min(n, Self.maxLength)
    }

    private var dotCount: Int { fixedLength ?? max(Self.minLength, digits.count) }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.brandBackground.opacity(0.85)).background(.ultraThinMaterial).ignoresSafeArea()

            // Side by side: a 4-row pad doesn't fit under the header on a 1080-point screen.
            HStack(alignment: .center, spacing: 140) {
                VStack(spacing: 36) {
                    ProfileAvatar(profile: profile, size: 180)
                    Text("Enter PIN for \(profile.name)")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    dots
                        .modifier(Shake(animatableData: CGFloat(shakes)))
                        .accessibilityElement()
                        .accessibilityLabel(Text("PIN"))
                        .accessibilityValue(Text("\(digits.count) of \(dotCount) digits entered"))

                    Text(message ?? " ")
                        .font(.callout)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(height: 80, alignment: .top)
                        .accessibilityHidden(message == nil)

                    HStack(spacing: 40) {
                        Button("Cancel", action: onCancel)
                        if fixedLength == nil {
                            Button("OK", action: submit)
                                .disabled(digits.count < Self.minLength || isVerifying)
                        }
                    }
                    .focusSection()
                }
                .frame(width: 640)

                pad
                    .disabled(isVerifying)
            }
        }
        .defaultFocus($focusedKey, .digit(1))
        .onChange(of: focusedKey) { _, key in
            if key == .gap { focusedKey = .digit(0) }
        }
        .onExitCommand(perform: onCancel)
        .onAppear {
            message = notice
            isError = false
        }
    }

    // MARK: Pieces

    private var dots: some View {
        HStack(spacing: 28) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.7), lineWidth: 3)
                    .background(Circle().fill(i < digits.count ? Color.white : .clear))
                    .frame(width: 34, height: 34)
            }
        }
        .frame(height: 50)
        // Beside the dots, not in their row, so the dots never shift while verifying.
        .overlay(alignment: .trailing) {
            if isVerifying { ProgressView().offset(x: 70) }
        }
        .animation(.easeOut(duration: 0.12), value: digits.count)
    }

    private var pad: some View {
        Grid(horizontalSpacing: 34, verticalSpacing: 30) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in
                        key(.digit(row * 3 + col))
                    }
                }
            }
            GridRow {
                // Invisible stand-in under 7: Down from 7 lands here and moves on to 0.
                Color.clear.frame(width: PadKeyStyle.size, height: PadKeyStyle.size)
                    .focusable()
                    .focused($focusedKey, equals: .gap)
                    .accessibilityHidden(true)
                key(.digit(0))
                key(.delete)
            }
        }
        .focusSection()
    }

    private func key(_ key: PadKey) -> some View {
        Button { press(key) } label: {
            switch key {
            case let .digit(n): Text(String(n)).font(.system(size: 54, weight: .medium)).monospacedDigit()
            case .delete: Image(systemName: "delete.left").font(.system(size: 40, weight: .medium))
            case .gap: EmptyView()
            }
        }
        .buttonStyle(PadKeyStyle())
        .focused($focusedKey, equals: key)
        .accessibilityLabel(key.accessibilityLabel)
    }

    // MARK: Input

    private func press(_ key: PadKey) {
        guard !isVerifying else { return }
        switch key {
        case let .digit(n):
            guard digits.count < (fixedLength ?? Self.maxLength) else { return }
            if digits.isEmpty { message = nil }
            digits.append(String(n))
            if let fixedLength, digits.count == fixedLength { submit() }
        case .delete:
            if !digits.isEmpty { digits.removeLast() }
        case .gap:
            break
        }
    }

    private func submit() {
        guard !isVerifying, digits.count >= Self.minLength else { return }
        let entered = digits
        isVerifying = true
        Task {
            let result = await verify(entered)
            isVerifying = false
            switch result {
            case .unlocked:
                break  // the presenter dismisses
            case .wrong:
                digits = ""
                message = String(localized: "Incorrect PIN. Try again.")
                isError = true
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
                focusedKey = .digit(1)
            case let .failed(text):
                message = text
                isError = true
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
        }
    }
}

enum PadKey: Hashable {
    case digit(Int)
    case delete
    case gap

    var accessibilityLabel: Text {
        switch self {
        case let .digit(n): Text(verbatim: String(n))
        case .delete: Text("Delete")
        case .gap: Text(verbatim: "")
        }
    }
}

/// Round key that lifts on focus, like the system passcode pad.
private struct PadKeyStyle: ButtonStyle {
    static let size: CGFloat = 120

    func makeBody(configuration: Configuration) -> some View {
        Key(configuration: configuration)
    }

    private struct Key: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .frame(width: PadKeyStyle.size, height: PadKeyStyle.size)
                .background(Circle().fill(isFocused ? Color.white : Color.white.opacity(0.14)))
                .scaleEffect(configuration.isPressed ? 1.0 : isFocused ? 1.12 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 16, y: 10)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Horizontal shake for a rejected PIN.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 24 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// Asks for a PIN when a request hits a locked profile mid-session
/// (`AppSession.pinChallenge`), over whatever screen is showing.
struct ProfileLockPrompt: ViewModifier {
    @ObservedObject var session: AppSession

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { session.pinChallenge }, set: { _ in })) { challenge in
                PINEntryView(
                    profile: challenge.profile,
                    notice: String(localized: "This profile is locked. Enter its PIN to continue."),
                    verify: { await session.verifyChallenge(pin: $0) },
                    onCancel: { session.cancelChallenge() }
                )
            }
    }
}
