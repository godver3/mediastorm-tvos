#if os(iOS)
import SwiftUI

/// Phone PIN entry, laid out like the system passcode screen: avatar, dots, a 3×4 keypad and
/// Cancel. Same contract as the TV's `PINEntryView`: fixed-length PINs submit on the last
/// digit, otherwise OK submits; a wrong PIN shakes and clears the dots.
struct MobilePINEntryView: View {
    let profile: Profile
    var notice: String?
    let verify: (String) async -> PINVerification
    let onCancel: () -> Void

    @State private var digits = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isVerifying = false
    @State private var shakes = 0

    private var fixedLength: Int? {
        guard let n = profile.pinLength, n >= PINEntryView.minLength else { return nil }
        return min(n, PINEntryView.maxLength)
    }

    private var dotCount: Int { fixedLength ?? max(PINEntryView.minLength, digits.count) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            ProfileAvatar(profile: profile, size: 84)
            Text("Enter PIN for \(profile.name)")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            dots
                .modifier(MobileShake(animatableData: CGFloat(shakes)))
                .accessibilityElement()
                .accessibilityLabel(Text("PIN"))
                .accessibilityValue(Text("\(digits.count) of \(dotCount) digits entered"))

            Text(message ?? " ")
                .font(.footnote)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)

            pad.disabled(isVerifying)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                if fixedLength == nil {
                    Button("OK", action: submit)
                        .fontWeight(.semibold)
                        .disabled(digits.count < PINEntryView.minLength || isVerifying)
                }
            }
            .font(.body)
            .padding(.horizontal, 44)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            message = notice
            isError = false
        }
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    .background(Circle().fill(i < digits.count ? Color.white : .clear))
                    .frame(width: 14, height: 14)
            }
        }
        .frame(height: 24)
        .overlay(alignment: .trailing) {
            if isVerifying { ProgressView().offset(x: 36) }
        }
        .animation(.easeOut(duration: 0.12), value: digits.count)
    }

    private var pad: some View {
        Grid(horizontalSpacing: 26, verticalSpacing: 16) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in key(.digit(row * 3 + col)) }
                }
            }
            GridRow {
                Color.clear.frame(width: MobilePadKeyStyle.size, height: MobilePadKeyStyle.size)
                key(.digit(0))
                key(.delete)
            }
        }
    }

    private func key(_ key: PadKey) -> some View {
        Button { press(key) } label: {
            switch key {
            case let .digit(n): Text(String(n)).font(.system(size: 34, weight: .regular)).monospacedDigit()
            case .delete: Image(systemName: "delete.left").font(.system(size: 24))
            case .gap: EmptyView()
            }
        }
        .buttonStyle(MobilePadKeyStyle(plain: key == .delete))
        .accessibilityLabel(key.accessibilityLabel)
    }

    private func press(_ key: PadKey) {
        guard !isVerifying else { return }
        switch key {
        case let .digit(n):
            guard digits.count < (fixedLength ?? PINEntryView.maxLength) else { return }
            if digits.isEmpty { message = nil }
            digits.append(String(n))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let fixedLength, digits.count == fixedLength { submit() }
        case .delete:
            if !digits.isEmpty { digits.removeLast() }
        case .gap:
            break
        }
    }

    private func submit() {
        guard !isVerifying, digits.count >= PINEntryView.minLength else { return }
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
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            case let .failed(text):
                message = text
                isError = true
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
        }
    }
}

/// Round passcode key that dims while pressed.
private struct MobilePadKeyStyle: ButtonStyle {
    static let size: CGFloat = 76
    var plain = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(Color.white.opacity(plain ? 0 : configuration.isPressed ? 0.4 : 0.14)))
            .contentShape(Circle())
    }
}

private struct MobileShake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(animatableData * .pi * 6), y: 0))
    }
}
#endif
