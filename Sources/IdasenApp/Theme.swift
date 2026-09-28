import AppKit
import IdasenKit
import SwiftUI

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

struct MotionPreferences: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.appReduceMotion, systemReduceMotion || reduceMotion)
            .transaction { transaction in
                if systemReduceMotion || reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}

// MARK: - Tokens

enum Theme {
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 18

    static func colorScheme(_ theme: AppTheme) -> ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func accent(_ choice: AccentChoice) -> Color {
        Color(nsColor: choice.color)
    }

    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.85), color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Window backgrounds

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// A quiet accent wash behind the content.
struct AmbientBackground: View {
    var accent: Color

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground)
            LinearGradient(
                colors: [
                    accent.opacity(0.09),
                    accent.opacity(0.015),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cards

struct ContentCard<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    var radius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pills & badges

struct StatusPill: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    var text: String
    var symbol: String?
    var color: Color
    var pulsing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: pulsing && !reduceMotion)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

struct SignalBars: View {
    var bars: Int
    var color: Color = .secondary

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index <= bars ? color : color.opacity(0.22))
                    .frame(width: 3, height: 4 + CGFloat(index) * 3)
            }
        }
    }
}

// MARK: - Liquid Glass controls

/// Group neighboring control effects into one renderer. Keep the merge distance
/// below the layout gap so independent actions stay distinct at rest.
struct GlassControls<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    @ViewBuilder var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Apply after sizing and foreground modifiers; glass supplies its own optical
/// border, shadow and pointer response, without a painted background underneath.
struct GlassControlSurface: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = Theme.controlRadius
    var interactive = true
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive && isEnabled),
                in: .rect(cornerRadius: radius)
            )
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder((tint ?? .primary).opacity(0.2), lineWidth: 1)
                }
        }
    }
}

/// Stable identity for controls that enter or leave a shared glass group.
struct GlassControlIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffectID(id, in: namespace)
                .glassEffectTransition(.materialize)
        } else {
            content
        }
    }
}

struct GlassControlButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var radius: CGFloat = Theme.controlRadius

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(GlassControlSurface(tint: tint, radius: radius))
    }
}

// MARK: - Buttons

struct HoldButton: View {
    var symbol: String
    var title: String
    var tint: Color
    var enabled: Bool = true
    var height: CGFloat = 84
    var onActivate: (() -> Void)? = nil
    var onPress: () -> Void
    var onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .foregroundStyle(.primary)
        .modifier(GlassControlSurface(tint: isPressed ? tint : nil, interactive: enabled))
        .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !isPressed else { return }
                    isPressed = true
                    onPress()
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onRelease()
                }
        )
        .onChange(of: enabled) { _, enabled in
            if !enabled, isPressed {
                isPressed = false
                onRelease()
            }
        }
        .onDisappear {
            if isPressed {
                isPressed = false
                onRelease()
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .help("Press and hold to move \(title.lowercased())")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title) the desk")
        .accessibilityHint("Press and hold to move. Activate to move one nudge step.")
        .accessibilityAction {
            if enabled { onActivate?() }
        }
    }
}

/// Delegate interaction, focus, disabled contrast and material to the system.
struct ActionButtonStyle: PrimitiveButtonStyle {
    var tint: Color = .accentColor
    var filled: Bool = true
    var compact: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            if filled {
                Button(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .controlSize(compact ? .small : .large)
            } else {
                Button(configuration)
                    .buttonStyle(.glass)
                    .tint(tint)
                    .controlSize(compact ? .small : .large)
            }
        } else if filled {
            Button(configuration)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(compact ? .small : .large)
        } else {
            Button(configuration)
                .buttonStyle(.bordered)
                .controlSize(compact ? .small : .large)
        }
    }
}

struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.015
    var offset: CGFloat = -1

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .offset(y: hovering ? offset : 0)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.015, offset: CGFloat = -1) -> some View {
        modifier(HoverLift(scale: scale, offset: offset))
    }
}

// MARK: - Misc

struct KeyHint: View {
    var keys: String
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(ActionButtonStyle(compact: true))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

extension Duration {
    static func seconds(_ value: Double) -> Duration {
        .milliseconds(Int(value * 1000))
    }
}

/// Keep fine numeric steps without rendering hundreds of macOS tick marks.
/// Keyboard and accessibility adjustments use the same step as pointer input.
struct PrecisionSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double

    init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double) {
        _value = value
        self.bounds = bounds
        self.step = step
    }

    var body: some View {
        Slider(value: Binding(
            get: { value },
            set: { value = clamp(($0 / step).rounded() * step) }
        ), in: bounds)
        .onKeyPress(.leftArrow) { adjust(-step); return .handled }
        .onKeyPress(.rightArrow) { adjust(step); return .handled }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(step)
            case .decrement: adjust(-step)
            @unknown default: break
            }
        }
    }

    private func clamp(_ value: Double) -> Double { min(bounds.upperBound, max(bounds.lowerBound, value)) }
    private func adjust(_ delta: Double) { value = clamp(value + delta) }
}
