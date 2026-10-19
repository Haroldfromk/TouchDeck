import AppKit
import CoreGraphics
import DeckKit
import Foundation
import Observation

/// 맥 화면 보기. 한 번에 기기 하나만 보고, 허락받은 접속의 봉투 안에서만 화면과 입력이 오간다.
@MainActor
@Observable
final class ScreenHost {
    /// 메뉴바에 "지금 화면을 보는 중"으로 보여줄 기기 이름
    private(set) var viewerName: String?
    private(set) var permission = ScreenPermission.granted
    /// 메뉴바에 보여줄 소리 상태. 소리를 안 보내면 nil
    private(set) var speakerNote: String?

    @ObservationIgnored private var viewer: ClientSession?
    @ObservationIgnored private var streamer: ScreenStreamer?
    /// 고른 모니터의 맥 전체 좌표(CGDisplayBounds)
    @ObservationIgnored private var display = CGRect.zero
    @ObservationIgnored private var gate = SendGate()
    @ObservationIgnored private var plan = PointerPlan()
    @ObservationIgnored private var lockWatch: Task<Void, Never>?
    /// 시작을 연달아 누르면 늦게 끝난 옛 시작이 새 스트림을 덮지 않게 번호로 구분한다
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var warnedNoInput = false
    @ObservationIgnored private var fps = ScreenFPS.low
    /// 보는 기기가 소리를 받겠다고 했는지
    @ObservationIgnored private var audioOn = false
    /// 소리 묶음은 작지만 와이파이가 막히면 쌓인다. 10개(약 0.1~0.2초)가 밀려 있으면 버린다
    @ObservationIgnored private var audioGate = SendGate(limit: 10)
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    init() {
        // 화면 보기 중에 맥 앱이 죽었으면 꺼 둔 맥 스피커를 되돌린다
        SpeakerMute.restore()
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopStream() }
            SpeakerMute.restoreAndWait()
        }
    }

    func refreshPermission() {
        permission = ScreenPermission.granted
    }

    func listDisplays(for session: ClientSession, allowed: Bool) {
        guard check(session, allowed: allowed) else { return }
        Task {
            let items = await DisplayCatalog.list()
            // 모니터가 하나도 안 잡히면 권한 문제다 (권한을 켠 뒤 앱을 다시 실행하지 않았을 때 이렇게 된다)
            session.send(items.isEmpty ? .screenStatus(.noPermission, message: nil) : .displays(items))
        }
    }

    func start(_ session: ClientSession, displayId: UInt32, maxSide: Int, fps: Int, audio: Bool, allowed: Bool) {
        guard check(session, allowed: allowed) else { return }
        stopStream()
        generation += 1
        let current = generation
        viewer = session
        viewerName = session.deviceName ?? "기기"
        warnedNoInput = false
        self.fps = fps
        audioOn = audio
        let onPacket: @Sendable (VideoPacket) -> Void = { [weak self] packet in
            Task { @MainActor in self?.deliver(packet, generation: current) }
        }
        let onAudio: @Sendable (AudioPacket) -> Void = { [weak self] packet in
            Task { @MainActor in self?.deliverAudio(packet, generation: current) }
        }
        let onStop: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, current == self.generation else { return }
                self.viewer?.send(.screenStatus(.stopped, message: nil))
                self.stopStream()
            }
        }
        Task {
            let streamer: ScreenStreamer
            do {
                streamer = try await ScreenStreamer.start(displayId: displayId, maxSide: maxSide, fps: fps,
                                                          onPacket: onPacket, onAudio: onAudio, onStop: onStop)
            } catch {
                print("[screen] start failed:", error)
                guard current == generation else { return }
                let missing = (error as? ScreenStreamer.StartError) == .noDisplay
                session.send(.screenStatus(.stopped, message: missing ? "모니터를 찾지 못했어요" : "화면을 찍지 못했어요"))
                stopStream()
                return
            }
            guard current == generation else { return streamer.stop() }
            self.streamer = streamer
            self.display = CGDisplayBounds(displayId)
            // 시작하는 사이에 fps를 바꿨으면 따라간다
            if self.fps != fps { streamer.setFrameRate(self.fps) }
            gate = SendGate(limit: SendGate.limit(forFPS: self.fps))
            audioGate = SendGate(limit: 10)
            print("[screen] start", viewerName ?? "?", displayId, streamer.width, streamer.height, "\(self.fps)fps", audioOn ? "audio" : "")
            session.send(.screenStarted(displayId: displayId, width: streamer.width, height: streamer.height))
            if audioOn { muteSpeaker(generation: current) }
            watchLock()
        }
    }

    /// 보는 중에 30/60이나 소리를 바꾼다. 보고 있는 기기만
    func options(_ session: ClientSession, fps: Int, audio: Bool) {
        guard session === viewer else { return }
        if fps != self.fps {
            self.fps = fps
            streamer?.setFrameRate(fps)
            gate.limit = SendGate.limit(forFPS: fps)
        }
        guard audio != audioOn else { return }
        audioOn = audio
        if !audio {
            SpeakerMute.restore()
            speakerNote = nil
        } else if streamer != nil {
            // 아직 시작하는 중이면 시작이 끝날 때 끈다
            muteSpeaker(generation: generation)
        }
    }

    func stop(_ session: ClientSession) {
        guard session === viewer else { return }
        stopStream()
    }

    func requestKeyframe(_ session: ClientSession) {
        guard session === viewer else { return }
        streamer?.requestKeyframe()
    }

    func pointer(_ event: PointerEvent, from session: ClientSession) {
        guard session === viewer, streamer != nil, !ScreenLock.isLocked else { return }
        guard MediaKey.allowed else {
            if !warnedNoInput { session.send(.screenStatus(.noInput, message: nil)) }
            warnedNoInput = true
            return
        }
        PointerInjector.post(plan.steps(for: event, display: display, now: .now))
    }

    /// 보기 화면 입력칸의 글. 화면 조작과 같은 조건(보는 기기, 스트림 있음, 안 잠김)에서만 넣는다
    func typeText(_ text: String, from session: ClientSession) {
        guard canType(from: session) else { return }
        // 보내는 쪽이 고장 나도 중간에 엔터가 눌리지 않게 맥에서도 다시 다듬는다
        let cleaned = TextInput.clean(text)
        guard !cleaned.isEmpty else { return }
        RemoteTyper.shared.type(cleaned)
    }

    func pressKey(_ key: RemoteKey, from session: ClientSession) {
        guard canType(from: session) else { return }
        RemoteTyper.shared.press(key)
    }

    private func canType(from session: ClientSession) -> Bool {
        guard session === viewer, streamer != nil, !ScreenLock.isLocked else { return false }
        guard MediaKey.allowed else {
            if !warnedNoInput { session.send(.screenStatus(.noInput, message: nil)) }
            warnedNoInput = true
            return false
        }
        return true
    }

    /// 맥 메뉴의 "끊기"
    func disconnect() {
        viewer?.send(.screenStatus(.stopped, message: "맥에서 화면 보기를 끊었어요"))
        stopStream()
    }

    func sessionDropped(_ session: ClientSession) {
        guard session === viewer else { return }
        stopStream()
    }

    /// 화면 보기 허용을 껐거나 허락을 취소했다. 보고 있었으면 바로 끊는다.
    func deviceDisallowed(_ deviceId: String) {
        guard viewer?.deviceId == deviceId else { return }
        viewer?.send(.screenStatus(.notAllowed, message: nil))
        stopStream()
    }

    // MARK: -

    /// 허용, 화면 기록 권한, 잠김, 다른 기기가 보는 중인지. 안 되면 이유를 보내고 false
    private func check(_ session: ClientSession, allowed: Bool) -> Bool {
        refreshPermission()
        let state = ScreenAccess.decide(allowed: allowed, permission: permission, locked: ScreenLock.isLocked,
                                        viewer: viewer?.deviceId, requester: session.deviceId ?? "")
        guard state == .ok else {
            // 권한을 아직 안 물었으면 맥에 시스템 창이 뜬다 (맥 메뉴에도 켜는 곳을 보여준다)
            if state == .noPermission { ScreenPermission.request() }
            session.send(.screenStatus(state, message: state == .busy ? viewerName : nil))
            return false
        }
        return true
    }

    private func deliver(_ packet: VideoPacket, generation current: Int) {
        guard current == generation, streamer != nil, let viewer else { return }
        // 보내는 중인 프레임이 밀려 있으면 버리고, 키프레임으로 다시 따라잡는다
        guard gate.begin(keyframe: packet.keyframe) else {
            if gate.takeKeyframeRequest() { streamer?.requestKeyframe() }
            return
        }
        viewer.sendBinary(packet.encoded()) { [weak self] in
            MainActor.assumeIsolated { self?.gate.finish() }
        }
    }

    private func deliverAudio(_ packet: AudioPacket, generation current: Int) {
        guard current == generation, streamer != nil, audioOn, let viewer else { return }
        // 소리엔 키프레임이 없다. 모든 묶음을 같은 무게로 세고, 키프레임 요청 신호는 읽지 않는다
        guard audioGate.begin(keyframe: true) else { return }
        viewer.sendBinary(packet.encoded()) { [weak self] in
            MainActor.assumeIsolated { self?.audioGate.finish() }
        }
    }

    /// 소리를 아이패드로 보내는 동안 맥 스피커를 끈다. 결과는 메뉴바에 보여준다
    private func muteSpeaker(generation current: Int) {
        SpeakerMute.mute { [weak self] start in
            Task { @MainActor in
                guard let self, current == self.generation, self.audioOn else { return }
                self.speakerNote = switch start {
                case .muted: "소리를 아이패드로 보내는 중 (맥 스피커 꺼 둠)"
                case .alreadyMuted: "소리를 아이패드로 보내는 중"
                case .cannotMute: "소리를 아이패드로 보내는 중 (맥 스피커를 끌 수 없는 장치예요)"
                }
            }
        }
    }

    /// 보는 동안 1초마다: 맥이 잠기면 화면 보기를 멈춘다
    private func watchLock() {
        lockWatch?.cancel()
        lockWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.viewer != nil else { return }
                if ScreenLock.isLocked {
                    self.viewer?.send(.screenStatus(.locked, message: nil))
                    self.stopStream()
                    return
                }
            }
        }
    }

    /// 끝나는 모든 길(닫기, 끊김, 잠김, 메뉴 "끊기", 허용 끄기, 앱 종료)이 여기를 지난다
    private func stopStream() {
        // 우리가 끈 맥 스피커만 되돌린다. 끄기가 아직 도는 중이어도 그 뒤에 되돌린다
        SpeakerMute.restore()
        speakerNote = nil
        audioOn = false
        PointerInjector.post(plan.release())
        streamer?.stop()
        streamer = nil
        if viewer != nil { print("[screen] stop", viewerName ?? "?") }
        viewer = nil
        viewerName = nil
        generation += 1
        lockWatch?.cancel()
        lockWatch = nil
    }
}
