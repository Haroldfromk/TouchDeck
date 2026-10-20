import AVFoundation
import DeckKit

/// 맥에서 온 소리 묶음(16비트)을 바로 튼다. 짧게 쌓아 두고 틀어서(AudioJitter) 끊기지 않게,
/// 쌓인 양이 늘면 버려서 소리가 점점 늦어지지 않게 한다.
@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 플레이어를 이은 형식. 맥이 다른 형식을 보내면 다시 잇는다
    private var format: AVAudioFormat?
    private var limits = AudioJitter.Limits.home
    private var jitter = AudioJitter()
    private var running = false
    /// 멈추거나 다시 이은 뒤 늦게 오는 "다 틀었다" 알림을 무시한다
    private var generation = 0

    init() {
        engine.attach(player)
        // 이어폰을 꽂는 것처럼 출력이 바뀌면 엔진이 멈춘다. 다음 묶음이 올 때 다시 잇는다
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.format = nil }
        }
    }

    /// remote: 원격(LTE)이면 더 쌓아 두고 튼다. 연결이 바뀌면 stop() 뒤 다시 불린다
    func start(remote: Bool) {
        guard !running else { return }
        limits = remote ? .remote : .home
        jitter = AudioJitter(limits: limits)
        let session = AVAudioSession.sharedInstance()
        // 무음 스위치를 켜 둬도 들리게
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
        running = true
    }

    func enqueue(_ packet: AudioPacket) {
        guard running else { return }
        let frames = packet.samples.count / packet.channels
        guard frames > 0 else { return }
        // 전화 같은 끼어들기로 엔진이 멈췄으면 다시 잇는다 (멈춘 엔진에서 play()를 부르면 앱이 죽는다)
        if !engine.isRunning { format = nil }
        if format?.sampleRate != Double(packet.sampleRate) || format?.channelCount != AVAudioChannelCount(packet.channels) {
            connect(sampleRate: packet.sampleRate, channels: packet.channels)
        }
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        let channels = packet.channels
        packet.samples.withUnsafeBufferPointer { samples in
            for frame in 0..<frames {
                for channel in 0..<channels {
                    out[channel][frame] = Float(samples[frame * channels + channel]) / 32767
                }
            }
        }
        // 실제로 넣을 수 있는 묶음만 센다
        let seconds = Double(frames) / Double(packet.sampleRate)
        let decision = jitter.arrive(seconds)
        guard decision != .drop else { return }
        let current = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played(seconds, generation: current) }
        }
        if decision == .queueAndStart { player.play() }
    }

    func stop() {
        guard running else { return }
        running = false
        reset()
        engine.stop()
        format = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: -

    private func connect(sampleRate: Int, channels: Int) {
        reset()
        engine.stop()
        guard let made = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: AVAudioChannelCount(channels)) else {
            format = nil
            return
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: made)
        // 끼어들기가 끝난 뒤에는 세션도 꺼져 있을 수 있다
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            try engine.start()
            format = made
        } catch {
            print("[audio] engine start failed:", error)
            format = nil
        }
    }

    /// 쌓인 것을 비우고 처음부터 다시 쌓는다
    private func reset() {
        generation += 1
        player.stop()
        jitter = AudioJitter(limits: limits)
    }

    private func played(_ seconds: Double, generation current: Int) {
        guard current == generation else { return }
        // 다 틀어서 비었으면 멈추고, 다시 쌓이면(집 0.06초, 원격 0.2초) 튼다
        if jitter.finished(seconds) { player.pause() }
    }
}
