import AppKit
import SwiftUI

enum BaramTheme {
    static let accent = Color(red: 0.341, green: 0.808, blue: 0.682)
    static let accentInk = Color(red: 0.067, green: 0.235, blue: 0.188)
    static let background = adaptive(light: 0xF1F4F3, dark: 0x1C2122)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x242B2D)
    static let raised = adaptive(light: 0xE8EFEC, dark: 0x2C3536)
    static let stroke = adaptive(light: 0xD7E2DE, dark: 0x364244)
    static let secondaryText = adaptive(light: 0x65756E, dark: 0xA4B5AE)
    static let tertiaryText = adaptive(light: 0x81918A, dark: 0x7D9188)
    static let accentText = adaptive(light: 0x16785E, dark: 0x76DABF)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

struct BaramButtonStyle: ButtonStyle {
    var emphasized = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButton(configuration: configuration, emphasized: emphasized, compact: compact)
    }

    private struct InteractiveButton: View {
        let configuration: ButtonStyle.Configuration
        let emphasized: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var fill: Color {
            if emphasized { return BaramTheme.accent.opacity(isEnabled ? (hovering ? 0.88 : 1) : 0.28) }
            if configuration.isPressed && isEnabled { return BaramTheme.stroke.opacity(0.75) }
            return BaramTheme.raised.opacity(hovering && isEnabled ? 1 : 0)
        }

        var body: some View {
            configuration.label
                .foregroundStyle(emphasized ? BaramTheme.accentInk : Color.primary)
                .background(fill, in: RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
