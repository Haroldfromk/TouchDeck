import Carbon.HIToolbox
import CoreGraphics
import DeckKit
import Foundation

/// 잠금 화면에 비밀번호를 치고 엔터를 누른다. 묶음마다 아직 잠겨 있는지 다시 보고, 아니면 그 자리에서 멈춘다.
/// 안 잠긴 맥에 치면 앞에 떠 있는 앱에 비밀번호가 그대로 들어가기 때문이다. 친 글자는 어디에도 남기지 않는다
final class MacUnlocker: @unchecked Sendable {
    static let shared = MacUnlocker(post: RemoteTyper.postEvent, isLocked: { ScreenLock.isPasswordLocked }, pause: { usleep(2_000) })

    private let queue = DispatchQueue(label: "touchdeck.unlock")
    private let post: @Sendable (RemoteStep) -> Void
    private let isLocked: @Sendable () -> Bool
    private let pause: @Sendable () -> Void

    init(post: @escaping @Sendable (RemoteStep) -> Void, isLocked: @escaping @Sendable () -> Bool,
         pause: @escaping @Sendable () -> Void) {
        self.post = post
        self.isLocked = isLocked
        self.pause = pause
    }

    /// done(true): 다 치고 엔터까지. done(false): 잠겨 있지 않아서 중간에(또는 처음부터) 멈췄다
    func type(_ password: String, done: @escaping @Sendable (Bool) -> Void) {
        let chunks = TextInput.chunks(password)
        queue.async { [post, isLocked, pause] in
            for (i, chunk) in chunks.enumerated() {
                if i > 0 { pause() }
                guard isLocked() else { return done(false) }
                post(.text(chunk))
            }
            guard isLocked() else { return done(false) }
            post(.key(CGKeyCode(kVK_Return), []))
            done(true)
        }
    }
}
