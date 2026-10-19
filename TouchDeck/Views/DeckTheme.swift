import DeckKit
import SwiftUI

/// 모니터 옆 매크로 패드. 아노다이징 금속 본체 위에 키캡이 박혀 있는 느낌.
enum DeckTheme {
    static let body = Color(hex: 0x2A2D33)
    static let keycap = Color(hex: 0x3A3F47)
    static let keycapTop = Color(hex: 0x454A53)
    static let keyLip = Color(hex: 0x1E2025)
    static let socket = Color(hex: 0x23262B)
    static let legend = Color(hex: 0xECEAE4)
    static let legendDim = Color(hex: 0xECEAE4).opacity(0.55)
    static let failure = Color(hex: 0xF0556A)

    static let app = Color(hex: 0x4C8DF6)
    static let command = Color(hex: 0x3DBE8B)
    static let terminal = Color(hex: 0xF2A33A)
    static let volume = Color(hex: 0xA57CF0)

    static func accent(for action: ButtonAction) -> Color {
        switch action {
        case .app: app
        case .command: command
        case .terminal: terminal
        }
    }

    static func legendFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
