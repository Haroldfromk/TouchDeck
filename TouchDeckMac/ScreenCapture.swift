import AppKit
import CoreMedia
import DeckKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

/// 맥 모니터 목록과 미리보기. 왼쪽에 놓인 모니터부터.
enum DisplayCatalog {
    static func displays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
            .sorted { CGDisplayBounds($0.displayID).minX < CGDisplayBounds($1.displayID).minX }
    }

    @MainActor
    static func list() async -> [DisplayInfo] {
        guard let displays = try? await displays() else { return [] }
        var items: [DisplayInfo] = []
        for display in displays {
            let id = display.displayID
            items.append(DisplayInfo(id: id, name: name(for: id), width: display.width, height: display.height,
                                     thumbnail: await thumbnail(display)))
        }
        return items
    }

    @MainActor
    static func name(for id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "모니터 \(id)"
    }

    /// 긴 변 320px JPEG 한 장을 base64로. 목록을 열 때만 찍는다.
    static func thumbnail(_ display: SCDisplay) async -> String {
        let size = ScreenGeometry.fit(width: display.width, height: display.height, maxSide: ScreenGeometry.minSide)
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return "" }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return "" }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return "" }
        return (data as Data).base64EncodedString()
    }
}

/// 고른 모니터 하나를 찍어서(ScreenCaptureKit) 바로 H.264로 압축한다(VideoToolbox 하드웨어).
/// 찍기와 압축은 전용 큐 하나에서만 돌고, 묶음이 나오면 onPacket으로 넘긴다.
/// 맥 전체 소리도 같은 스트림에서 받아 16비트로 바꿔 onAudio로 넘긴다(보낼지는 받는 쪽이 정한다).
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let width: Int
    let height: Int
    private let queue = DispatchQueue(label: "touchdeck.screen")
    private let audioQueue = DispatchQueue(label: "touchdeck.screen.audio")
    private let onPacket: @Sendable (VideoPacket) -> Void
    private let onAudio: @Sendable (AudioPacket) -> Void
    private let onStop: @Sendable () -> Void
    private var stream: SCStream?
    /// 보는 중에 fps를 바꿀 때 고쳐서 다시 넘긴다
    private var config: SCStreamConfiguration?
    // 아래는 queue에서만 만진다
    private var fps: Int
    /// 원격처럼 좁은 길이면 아이패드가 상한을 준다. nil이면 40Mbps까지
    private var cap: Int?
    private var encoder: VTCompressionSession?
    private var forceKeyframe = true
    /// 화면이 멈춰 있으면 새 프레임이 안 온다. 키프레임을 달라고 하면 마지막 화면을 다시 압축한다
    private var lastFrame: CVPixelBuffer?

    // audioQueue에서만 만진다
    private var warnedAudioFormat = false

    init(width: Int, height: Int, fps: Int, cap: Int?, onPacket: @escaping @Sendable (VideoPacket) -> Void,
         onAudio: @escaping @Sendable (AudioPacket) -> Void, onStop: @escaping @Sendable () -> Void) {
        self.width = width
        self.height = height
        self.fps = fps
        self.cap = cap
        self.onPacket = onPacket
        self.onAudio = onAudio
        self.onStop = onStop
    }

    enum StartError: Error { case noDisplay }

    /// 모니터를 찾아 크기를 정하고 찍기 시작한다. SCDisplay는 여러 스레드에 넘길 수 없어서 찾기부터 여기서 한다.
    static func start(displayId: CGDirectDisplayID, maxSide: Int, fps: Int, cap: Int?, onPacket: @escaping @Sendable (VideoPacket) -> Void,
                      onAudio: @escaping @Sendable (AudioPacket) -> Void,
                      onStop: @escaping @Sendable () -> Void) async throws -> ScreenStreamer {
        guard let display = try await DisplayCatalog.displays().first(where: { $0.displayID == displayId }) else {
            throw StartError.noDisplay
        }
        // 포인트가 아니라 실제 픽셀 기준으로 맞춘다. 레티나 맥북은 1512포인트지만 픽셀은 3024라 절반으로 찍으면 흐리다
        let mode = CGDisplayCopyDisplayMode(displayId)
        let pixels = (width: mode?.pixelWidth ?? display.width, height: mode?.pixelHeight ?? display.height)
        let size = ScreenGeometry.fit(width: pixels.width, height: pixels.height, maxSide: maxSide)
        let streamer = ScreenStreamer(width: size.width, height: size.height, fps: fps, cap: cap, onPacket: onPacket, onAudio: onAudio, onStop: onStop)
        try await streamer.start(display: display)
        return streamer
    }

    private func start(display: SCDisplay) async throws {
        try queue.sync { try makeEncoder() }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = true
        config.queueDepth = 4
        // 원본 해상도로 찍은 뒤 줄인다 (기본값은 레티나에서 낮은 해상도로 찍을 수 있다)
        config.captureResolution = .best
        // 맥 전체 소리. 같은 화면 기록 권한으로 된다. TouchDeck 자신의 소리는 뺀다
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try await stream.startCapture()
        self.stream = stream
        self.config = config
    }

    /// 보는 중에 30/60을 바꾼다. 스트림을 다시 만들지 않는다
    func setFrameRate(_ fps: Int) {
        guard let stream, let config else { return }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        stream.updateConfiguration(config) { error in
            if let error { print("[screen] fps change failed:", error) }
        }
        queue.async {
            self.fps = fps
            guard let encoder = self.encoder else { return }
            VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
            VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate,
                                 value: Self.bitRate(width: self.width, height: self.height, fps: fps, cap: self.cap) as CFNumber)
        }
    }

    /// 보는 중에 비트레이트 상한을 바꾼다
    func setBitrateCap(_ cap: Int?) {
        queue.async {
            self.cap = cap
            guard let encoder = self.encoder else { return }
            VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate,
                                 value: Self.bitRate(width: self.width, height: self.height, fps: self.fps, cap: cap) as CFNumber)
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        queue.async {
            if let encoder = self.encoder { VTCompressionSessionInvalidate(encoder) }
            self.encoder = nil
            self.lastFrame = nil
        }
    }

    func requestKeyframe() {
        queue.async {
            self.forceKeyframe = true
            if let frame = self.lastFrame { self.encode(frame) }
        }
    }

    // MARK: - SCStreamOutput / SCStreamDelegate (queue에서 불린다)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            if let packet = audioPacket(from: sampleBuffer) { onAudio(packet) }
            return
        }
        // 화면이 그대로면 "변화 없음" 프레임이 온다. 실제로 그린 프레임만 압축한다
        guard type == .screen, Self.isComplete(sampleBuffer), let frame = sampleBuffer.imageBuffer else { return }
        lastFrame = frame
        encode(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[screen] stream stopped:", error)
        onStop()
    }

    // MARK: - 압축

    private func makeEncoder() throws {
        var session: VTCompressionSession?
        // 지연이 적은 실시간 모드 (B프레임 없음)
        let spec = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary
        let status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                codecType: kCMVideoCodecType_H264, encoderSpecification: spec,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else { throw NSError(domain: "TouchDeck.encoder", code: Int(status)) }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_ConstrainedHigh_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: Self.bitRate(width: width, height: height, fps: fps, cap: cap) as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        encoder = session
    }

    /// 글자가 많은 화면이라 넉넉하게(픽셀당 0.2비트 × 초당 장수). 와이파이가 버티게 40Mbps에서 멈춘다.
    /// 상한(cap)을 받으면 그보다도 넘지 않는다
    static func bitRate(width: Int, height: Int, fps: Int, cap: Int?) -> Int {
        min(Int(Double(width * height) * Double(fps) * 0.2), cap ?? 40_000_000)
    }

    private func encode(_ frame: CVPixelBuffer) {
        guard let encoder else { return }
        var properties: CFDictionary?
        if forceKeyframe {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            forceKeyframe = false
        }
        // 다시 압축하는 마지막 화면도 시간이 앞으로만 가게 지금 시각을 쓴다
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let onPacket = onPacket
        VTCompressionSessionEncodeFrame(encoder, imageBuffer: frame, presentationTimeStamp: now, duration: .invalid,
                                        frameProperties: properties, infoFlagsOut: nil) { status, _, sample in
            guard status == noErr, let sample, let packet = Self.packet(from: sample) else { return }
            onPacket(packet)
        }
    }

    /// 맥이 주는 소리(32비트 실수, 보통 채널별로 따로) → 16비트 소리 묶음. 다른 형식이면 버린다
    private func audioPacket(from sample: CMSampleBuffer) -> AudioPacket? {
        guard let format = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32, asbd.mChannelsPerFrame > 0 else {
            if !warnedAudioFormat { print("[screen] unsupported audio format") }
            warnedAudioFormat = true
            return nil
        }
        let channels = Int(asbd.mChannelsPerFrame)
        let separate = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let planar: [[Float]]? = try? sample.withAudioBufferList { list, _ in
            if separate {
                return list.map { buffer in
                    guard let data = buffer.mData else { return [] }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
                }
            }
            guard let buffer = list.first, let data = buffer.mData else { return [] }
            let all = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                          count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            return (0..<channels).map { channel in stride(from: channel, to: all.count, by: channels).map { all[$0] } }
        }
        guard let planar, !planar.isEmpty else { return nil }
        let samples = AudioPacket.interleave(planar)
        guard !samples.isEmpty else { return nil }
        return AudioPacket(channels: planar.count, sampleRate: Int(asbd.mSampleRate), samples: samples)
    }

    private static func isComplete(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }

    /// 압축된 프레임 → 영상 묶음. 키프레임이면 SPS/PPS를 같이 싣는다.
    static func packet(from sample: CMSampleBuffer) -> VideoPacket? {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
        var sets: [Data] = []
        if keyframe, let format = sample.formatDescription {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                               parameterSetSizeOut: nil, parameterSetCountOut: &count,
                                                               nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &pointer,
                                                                   parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                   nalUnitHeaderLengthOut: nil)
                if let pointer { sets.append(Data(bytes: pointer, count: size)) }
            }
        }
        guard let data = try? sample.dataBuffer?.dataBytes() else { return nil }
        return VideoPacket(keyframe: keyframe, parameterSets: sets, frame: data)
    }
}
