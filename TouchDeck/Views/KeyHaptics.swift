import SwiftUI
import UIKit

/// 키를 누른 느낌. 손가락이 닿는 순간 묵직하게(heavy) 울린다. 아이패드는 진동 장치가 없어 아무 일도 없다
@MainActor
enum KeyHaptics {
    /// 실기기에서 rigid는 약하다고 해서 heavy로 올렸다
    private static let pressGenerator = UIImpactFeedbackGenerator(style: .heavy)
    /// 연달아 울려도 하나하나 구분되게 짧고 또렷한 rigid. 0.4 세기는 실기기에서 안 느껴져 최대로 둔다
    private static let tickGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// 키가 눌려 들어가는 순간
    static func press() {
        pressGenerator.impactOccurred()
        // 다음 누름이 늦지 않게 진동 장치를 깨워 둔다
        pressGenerator.prepare()
    }

    /// ⌫를 누르고 있어 연달아 지울 때 톡톡
    static func tick() {
        tickGenerator.impactOccurred()
        tickGenerator.prepare()
    }
}

/// "닿음" 신호(onPressingChanged)는 짧게 탭하면 손을 뗀 뒤에야 오거나 아예 안 온다.
/// 닿을 때 울렸으면 탭 끝에서는 다시 울리지 않고, 못 울렸으면 그때 울린다. 한 번 누르면 꼭 한 번
struct PressHaptic {
    private var lastPress = Date.distantPast

    @MainActor
    mutating func touched() {
        KeyHaptics.press()
        lastPress = .now
    }

    @MainActor
    mutating func tapped() {
        if Date.now.timeIntervalSince(lastPress) > 0.5 { KeyHaptics.press() }
        lastPress = .distantPast
    }
}

/// Button용. isPressed는 손가락이 닿는 순간 true가 된다
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { KeyHaptics.press() }
            }
    }
}
