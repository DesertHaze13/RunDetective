import SwiftUI

func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(1) } }
func detail(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }.caseMotion(tint: .mint, scroll: false) }


struct AnimatedCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .rotationEffect(.degrees(configuration.isPressed && !reduceMotion ? -1.5 : 0))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.48), value: configuration.isPressed)
    }
}

struct CardClue: View {
    let lines: [String]
    @State private var tapCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.7)) { tapCount += 1 }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.title3)
                        .symbolEffect(.bounce, value: tapCount)
                    Text(tapCount == 0 ? "Reveal case note" : "Another case note")
                    Spacer(minLength: 4)
                    Image(systemName: "hand.tap").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.teal)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(AnimatedCardButtonStyle())
            if tapCount > 0 && !lines.isEmpty {
                Text(lines[(tapCount - 1) % lines.count])
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(tapCount)
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
        .accessibilityElement(children: .contain)
        .caseMotion(tint: .teal, scroll: false)
    }
}

extension View {
    func caseMotion(tint: Color, scroll: Bool = true, suppressTap: Bool = false) -> some View {
        modifier(CaseMotion(tint: tint, scroll: scroll, suppressTap: suppressTap))
    }
}

struct CaseMotion: ViewModifier {
    let tint: Color
    let scroll: Bool
    let suppressTap: Bool
    @State private var flashing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        let decorated = content
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(tint.opacity(flashing ? 0.85 : 0), lineWidth: 2.5)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) { spark("sparkle", x: -8, y: -12) }
            .overlay(alignment: .topTrailing) { spark("plus", x: 11, y: -10) }
            .overlay(alignment: .bottomLeading) { spark("plus", x: -11, y: 10) }
            .overlay(alignment: .bottomTrailing) { spark("sparkle", x: 9, y: 13) }
            .scaleEffect(flashing && !reduceMotion ? 0.975 : 1)
            .simultaneousGesture(TapGesture().onEnded { if !suppressTap { burst() } })
            .sensoryFeedback(.selection, trigger: flashing)

        if scroll && !reduceMotion {
            decorated.scrollTransition(.animated(.spring(response: 0.58, dampingFraction: 0.73))) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.86)
                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                    .offset(y: phase.isIdentity ? 0 : 18)
            }
        } else {
            decorated
        }
    }

    private func spark(_ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 23, weight: .bold))
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.65), radius: 10)
            .scaleEffect(flashing && !reduceMotion ? 1.2 : 0.15)
            .opacity(flashing && !reduceMotion ? 1 : 0)
            .offset(x: flashing ? x : 0, y: flashing ? y : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func burst() {
        guard !reduceMotion else { return }
        flashing = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.48)) { flashing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.35)) { flashing = false }
        }
    }
}

struct AmbientBackdrop: View {
    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                Circle()
                    .fill(.mint.opacity(0.15))
                    .frame(width: 360, height: 360)
                    .blur(radius: 74)
                    .offset(x: drifting ? geometry.size.width * 0.32 : -geometry.size.width * 0.22,
                            y: drifting ? -110 : 220)
                Circle()
                    .fill(.indigo.opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 72)
                    .offset(x: drifting ? -geometry.size.width * 0.35 : geometry.size.width * 0.34,
                            y: drifting ? geometry.size.height * 0.58 : geometry.size.height * 0.25)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drifting = true }
        }
    }
}

struct RunnerGlass: View {
    let trigger: Int
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .frame(width: 58, height: 58)
                .offset(x: -7, y: 7)
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.14))
                .frame(width: 58, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.4), lineWidth: 1)
                }
            Image(systemName: "figure.run")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: trigger)
        }
        .frame(width: 72, height: 72)
        .offset(x: reduceMotion ? 0 : (floating ? 4 : -4), y: reduceMotion ? 0 : (floating ? -5 : 4))
        .rotationEffect(.degrees(reduceMotion ? 0 : (floating ? 5 : -4)))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { floating = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DetectiveBadge: View {
    let symbol: String
    let tint: Color
    @State private var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 50, height: 50)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .offset(y: reduceMotion ? 0 : (lifted ? -5 : 2))
            .rotationEffect(.degrees(reduceMotion ? 0 : (lifted ? 5 : -4)))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { lifted = true }
            }
            .accessibilityHidden(true)
    }
}
