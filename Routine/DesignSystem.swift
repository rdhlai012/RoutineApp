import SwiftUI
import UIKit

/// One place for every colour, metric and surface in the app.
///
/// Colour discipline, deliberately narrow:
///   - Blue   is the only interaction colour.
///   - Orange means prayer, and nothing else.
///   - Green  means completed, and nothing else.
enum RT {

    // MARK: Colour

    /// True black, so OLED pixels are actually off.
    static let background = Color.black
    /// Content cards sit just above the background, never glass.
    static let surface = Color.white.opacity(0.06)
    static let surfaceRaised = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.10)

    static let accent = Color.accentColor
    static let prayer = Color.orange
    static let done = Color.green

    static let label = Color.white
    static let secondaryLabel = Color.white.opacity(0.62)
    static let tertiaryLabel = Color.white.opacity(0.38)

    // MARK: Metric

    static let cardRadius: CGFloat = 16
    static let heroRadius: CGFloat = 24
    static let screenPadding: CGFloat = 24
    static let cardPadding: CGFloat = 20
    /// Gap between top-level sections on a screen.
    static let sectionSpacing: CGFloat = 28
    /// Clears the floating tab bar at the bottom of a scroll view.
    static let tabBarClearance: CGFloat = 96
    /// Apple's minimum comfortable hit target.
    static let minTarget: CGFloat = 44
}

// MARK: - Surfaces

/// A content card. Per the HIG, Liquid Glass belongs to floating navigation and
/// controls, not to the content underneath them, so content cards use an opaque
/// raised fill and keep glass for the things that actually float.
struct CardBackground: ViewModifier {
    var radius: CGFloat = RT.cardRadius
    var padding: CGFloat? = RT.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(RT.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(RT.hairline, lineWidth: 0.5)
            )
    }
}

/// A genuinely floating surface, rendered with Liquid Glass.
///
/// The deployment target is iOS 26.0, so this calls `glassEffect` directly with
/// no availability dance. `interactive` makes the glass respond to touch and is
/// meant for controls, not for passive panels.
struct FloatingGlass: ViewModifier {
    var radius: CGFloat = RT.heroRadius
    var interactive: Bool = false

    func body(content: Content) -> some View {
        content.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

extension View {
    func card(radius: CGFloat = RT.cardRadius, padding: CGFloat? = RT.cardPadding) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }

    func floatingGlass(radius: CGFloat = RT.heroRadius, interactive: Bool = false) -> some View {
        modifier(FloatingGlass(radius: radius, interactive: interactive))
    }

    /// Standard screen chrome: black canvas, edge padding, tab-bar clearance.
    func routineScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(RT.background.ignoresSafeArea())
    }
}

/// Section heading used above every group on a screen.
struct SectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    init(_ title: String) {
        self.title = title
        self.action = nil
    }

    init(_ title: String, actionTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.action = (actionTitle, action)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(RT.label)
            Spacer()
            if let action = action {
                Button(action.title, action: action.run)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(RT.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Haptics

/// Thin wrapper so call sites read as intent rather than as UIKit noise.
enum Haptics {
    static func completed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func uncompleted() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Motion

extension Animation {
    /// The single spring used for every completion interaction, so the whole
    /// app moves with one personality.
    static let routineSpring = Animation.spring(response: 0.34, dampingFraction: 0.72)
    static let routineRing = Animation.spring(response: 0.6, dampingFraction: 0.85)
}

// MARK: - Prayer presentation

extension Prayer {
    /// SF Symbols rather than emoji: they respect Dynamic Type, tint and
    /// VoiceOver, and they look native. Orange is applied by the caller.
    var symbolName: String {
        switch self {
        case .fajr: return "moon.stars.fill"
        case .dhuhr: return "sun.max.fill"
        case .asr: return "sun.haze.fill"
        case .maghrib: return "sunset.fill"
        case .isha: return "moon.fill"
        }
    }
}

extension DayState {
    var color: Color {
        switch self {
        case .complete: return RT.done
        case .partial: return .yellow
        case .missed: return .red
        case .noData: return Color.white.opacity(0.18)
        }
    }
}

extension SleepStatus {
    var color: Color {
        switch self {
        case .meetsGoal: return RT.done
        case .meetsMinimum: return .yellow
        case .belowMinimum: return .red
        }
    }
}
