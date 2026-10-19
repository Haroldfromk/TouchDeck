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

    func refreshPermission() {
        permission = ScreenPermission.granted
    }

    func listDisplays(for session: ClientSession, allowed: Bool) {
        guard check(session, allowed: allowed) else { return }
        Task { session.send(.displays(await DisplayCatalog.list())) }
    }

    func start(_ session: ClientSession, displayId: UInt32, maxSide: Int, allowed: Bool) {
        guard check(session, allowed: allowed) else { return }
        stopStream()
        generation += 1
        let current = generation
        viewer = session
        viewerName = session.deviceName ?? "기기"
        warnedNoInput = false
        let onPacket: @Sendable (VideoPacket) -> Void = { [weak self] packet in
            Task { @MainActor in self?.deliver(packet, generation: current) }
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
                streamer = try await ScreenStreamer.start(displayId: displayId, maxSide: maxSide, onPacket: onPacket, onStop: onStop)
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
            gate = SendGate()
            print("[screen] start", viewerName ?? "?", displayId, streamer.width, streamer.height)
            session.send(.screenStarted(displayId: displayId, width: streamer.width, height: streamer.height))
            watchLock()
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

    private func stopStream() {
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
