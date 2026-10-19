import Foundation

/// 화면 보기로 소리를 아이패드에 보내는 동안 맥 스피커를 꺼 둔다.
/// 원래 꺼져 있었으면 건드리지 않고, 우리가 끈 것만 기록해 두었다가 되돌린다.
/// 맥 앱이 중간에 죽어도 다음에 켤 때 기록을 보고 되돌린다.
enum SpeakerMute {
    /// 무엇을 껐는지. 맥에 저장해 둔다
    struct Record: Codable, Equatable {
        enum Kind: String, Codable { case system, betterDisplay }
        var kind: Kind
        /// BetterDisplay로 끈 모니터 이름
        var name: String?
    }

    enum Start: Equatable {
        case muted(Record)
        /// 원래 꺼져 있었다. 끝날 때도 켜지 않는다
        case alreadyMuted
        /// macOS도 BetterDisplay도 모르는 장치. 소리는 그대로 보낸다
        case cannotMute
    }

    static let defaultsKey = "touchdeck.speakerMuteRecord"

    // MARK: - 판단 (테스트 대상)

    static func plan(source: VolumeController.Source, alreadyMuted: Bool) -> Start {
        if alreadyMuted { return .alreadyMuted }
        switch source {
        case .system: return .muted(Record(kind: .system, name: nil))
        case .betterDisplay(let name): return .muted(Record(kind: .betterDisplay, name: name))
        case .none: return .cannotMute
        }
    }

    /// 켜질 때 남아 있는 기록. 깨졌으면 nil
    static func restoreOnLaunch(stored: Data?) -> Record? {
        stored.flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    // MARK: - 바깥과 닿는 부분

    /// 끄기와 되돌리기는 프로세스를 띄워서 약 0.2초 걸린다. 한 줄로 세워서,
    /// 끄기가 끝나기 전에 보기가 멈춰도 되돌리기가 반드시 끄기 뒤에 오게 한다
    private static let queue = DispatchQueue(label: "touchdeck.speaker")

    static func mute(completion: @escaping @Sendable (Start) -> Void) {
        queue.async {
            let output = VolumeController.currentOutput()
            let start = plan(source: output.source, alreadyMuted: output.muted)
            if case .muted(let record) = start {
                // 끄기 전에 먼저 적어 둔다. 끄는 도중에 죽어도 다음에 켤 때 되돌린다
                UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: defaultsKey)
                VolumeController.setMuted(true, on: record)
            }
            completion(start)
        }
    }

    /// 기록이 있으면 그 길로 켜고 지운다. 없으면 아무것도 안 한다
    static func restore() {
        queue.async(execute: restoreNow)
    }

    /// 앱 종료 때. 끝날 때까지 기다린다
    static func restoreAndWait() {
        queue.sync(execute: restoreNow)
    }

    private static func restoreNow() {
        guard let record = restoreOnLaunch(stored: UserDefaults.standard.data(forKey: defaultsKey)) else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        VolumeController.setMuted(false, on: record)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
