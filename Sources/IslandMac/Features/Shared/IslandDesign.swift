import SwiftUI
import IslandCore

/// Shared look for every panel screen, modelled on the Dynamic Island and Control Center:
/// white and grey content on black, the system accent colour for selection and primary
/// actions, and green / orange / red only when they mean something (active, attention, destructive).
enum IslandDesign {
    // Layout
    static let contentWidth: CGFloat = 520
    static let gap: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 22
    static let rowRadius: CGFloat = 14
    static let iconButtonSize: CGFloat = 30

    // Neutrals (the panel is always dark)
    static let primary = Color.white
    static let secondary = Color(white: 0.62)
    static let tertiary = Color(white: 0.42)
    static let card = Color(white: 1, opacity: 0.06)
    static let cardHover = Color(white: 1, opacity: 0.09)
    static let fill = Color(white: 1, opacity: 0.14)
    static let fillStrong = Color(white: 1, opacity: 0.2)
    static let separator = Color(white: 1, opacity: 0.08)

    // Meaning
    /// The user's macOS accent colour (blue by default), as system controls use it.
    static let accent = Color(nsColor: .controlAccentColor)
    static let success = Color.green
    static let danger = Color.red
    static let warning = Color.orange
    /// Background strength for a tinted control (e.g. the orange pause button on a timer).
    static let tintBackground = 0.24

    // Type scale
    static let largeTitle = Font.system(size: 17, weight: .semibold)
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let footnote = Font.system(size: 10)
    static let metric = Font.system(size: 12, weight: .semibold, design: .rounded)
    /// Big glanceable figures, like "0:22" on a timer.
    static let display = Font.system(size: 26, weight: .regular, design: .rounded)
    /// Live Activity hero numbers ("$104.02", "22m"): heavy, rounded, tightly tracked.
    static let hero = Font.system(size: 30, weight: .bold, design: .rounded)
    static let heroTracking: CGFloat = -0.6
    /// Small uppercase captions under or above a value ("THIS MONTH").
    static let label = Font.system(size: 10, weight: .semibold)
    static let labelTracking: CGFloat = 0.6

    // Motion: critically damped by default (Apple ships damping 1.0, response ~0.35 for UI moves).
    static let spring = Animation.spring(response: 0.35, dampingFraction: 1)
    /// The island shape itself springs with a hint of overshoot, like the Dynamic Island.
    static let shapeResponse = 0.42
    static let shapeDamping = 0.78

    /// Transparent room around the surface so the spring's overshoot is never clipped.
    static let windowMargin: CGFloat = 16
}

extension View {
    /// An uppercase metric caption with positive tracking for legibility at small sizes.
    func islandLabel(_ color: Color = IslandDesign.secondary) -> some View {
        self.font(IslandDesign.label).tracking(IslandDesign.labelTracking).textCase(.uppercase).foregroundStyle(color)
    }

    /// A Live Activity hero figure.
    func islandHero(_ color: Color = IslandDesign.primary) -> some View {
        self.font(IslandDesign.hero).tracking(IslandDesign.heroTracking).monospacedDigit().foregroundStyle(color)
    }
}

/// Per-feature colours. Apple keeps chrome neutral, so most features are white (rendered grey
/// where a fill is needed); only Files and Agents use the system accent, like AirDrop and Messages.
enum IslandTint {
    /// Marks a colour as "no colour": controls and glyphs render it as neutral grey.
    static let neutral = Color.white
    static let home = neutral
    static let agents = IslandDesign.accent
    static let music = neutral
    static let files = IslandDesign.accent
    static let terminal = neutral
    static let settings = neutral
    static let codex = neutral
    static let claude = neutral

    static func feature(_ feature: IslandFeature) -> Color {
        switch feature {
        case .home: home
        case .agents: agents
        case .music: music
        case .files: files
        case .terminal: terminal
        }
    }
}

extension View {
    /// A rounded platter, like a widget or a Control Center module.
    func islandCard(padding: CGFloat = IslandDesign.cardPadding) -> some View {
        self.padding(padding)
            .background(IslandDesign.card, in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
    }
}

/// Instant press feedback (scale on press-down), per Apple's "respond on pointer-down".
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A small header that names a card: SF Symbol, title, and optional trailing accessory.
struct IslandCardHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    init(_ title: String, symbol: String, tint: Color = IslandDesign.secondary,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title; self.symbol = symbol; self.tint = tint; self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(IslandDesign.title).lineLimit(1)
            Spacer(minLength: 4)
            accessory
        }
    }
}

/// The system empty state, sized for the panel.
struct IslandEmptyState: View {
    let title: String
    let symbol: String
    var message: String?
    var tint: Color = IslandDesign.secondary

    var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
        } description: {
            if let message { Text(message).font(IslandDesign.callout).foregroundStyle(IslandDesign.secondary) }
        }
        .frame(width: IslandDesign.contentWidth)
        .padding(.vertical, 4)
    }
}

/// How a control uses its tint, following Apple's controls:
/// `plain` = grey (dismiss, secondary), `tinted` = tinted glyph on a faint tint (timer pause),
/// `filled` = solid tint (default action), `destructive` = red label on grey (action-sheet Delete).
enum IslandControlEmphasis { case plain, tinted, filled, destructive }

private func controlColors(_ emphasis: IslandControlEmphasis, tint: Color, pressed: Bool) -> (foreground: Color, background: Color) {
    let grey = pressed ? IslandDesign.fillStrong : IslandDesign.fill
    switch emphasis {
    case .plain: return (IslandDesign.primary, grey)
    case .destructive: return (IslandDesign.danger, grey)
    case .tinted:
        if tint == IslandTint.neutral { return (IslandDesign.primary, grey) }
        return (tint, tint.opacity(pressed ? IslandDesign.tintBackground + 0.12 : IslandDesign.tintBackground))
    case .filled: return (tint == IslandTint.neutral ? .black : .white, tint)
    }
}

/// A circular glyph button.
struct IslandIconButtonStyle: ButtonStyle {
    var size: CGFloat = IslandDesign.iconButtonSize
    var emphasis: IslandControlEmphasis = .plain
    var tint: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    /// `prominent` keeps older call sites working: a solid white circle.
    init(size: CGFloat = IslandDesign.iconButtonSize, prominent: Bool = false) {
        self.size = size; emphasis = prominent ? .filled : .plain; tint = .white
    }

    init(size: CGFloat = IslandDesign.iconButtonSize, emphasis: IslandControlEmphasis, tint: Color) {
        self.size = size; self.emphasis = emphasis; self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        let colors = controlColors(emphasis, tint: tint, pressed: configuration.isPressed)
        return configuration.label
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(colors.foreground)
            .frame(width: size, height: size)
            .background(colors.background, in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A capsule text button.
struct IslandPillButtonStyle: ButtonStyle {
    var emphasis: IslandControlEmphasis = .plain
    var tint: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    /// `prominent` keeps older call sites working: a solid white capsule.
    init(prominent: Bool = false) { emphasis = prominent ? .filled : .plain; tint = .white }

    init(emphasis: IslandControlEmphasis, tint: Color) { self.emphasis = emphasis; self.tint = tint }

    func makeBody(configuration: Configuration) -> some View {
        let colors = controlColors(emphasis, tint: tint, pressed: configuration.isPressed)
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14).frame(height: 30)
            .foregroundStyle(colors.foreground)
            .background(colors.background, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A white SF Symbol on a solid shape. Circles follow Control Center (grey when neutral,
/// solid colour when it means something); squircles follow System Settings row icons.
struct IslandGlyph: View {
    enum Shape { case circle, squircle }

    let symbol: String
    let tint: Color
    var size: CGFloat = 28
    var shape: Shape = .circle

    var body: some View {
        let background = tint == IslandTint.neutral ? IslandDesign.fill : tint
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(background, in: shape == .circle
                        ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)))
            .accessibilityHidden(true)
    }
}

/// A grouped list row, like System Settings: title on the left, control on the right.
struct IslandFormRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.subtitle = subtitle; self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(IslandDesign.body)
                if let subtitle { Text(subtitle).font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary) }
            }
            Spacer(minLength: 12)
            control
        }.padding(.horizontal, IslandDesign.cardPadding).frame(minHeight: 40)
    }
}

/// Groups `IslandFormRow`s in one platter. Put `IslandFormDivider()` between rows
/// (macOS 14 has no subview iteration, so separators are explicit).
struct IslandFormSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, 4)
            .background(IslandDesign.card, in: RoundedRectangle(cornerRadius: IslandDesign.rowRadius, style: .continuous))
    }
}

/// An inset hairline between grouped rows.
struct IslandFormDivider: View {
    var body: some View {
        Rectangle().fill(IslandDesign.separator).frame(height: 1).padding(.leading, IslandDesign.cardPadding)
    }
}
