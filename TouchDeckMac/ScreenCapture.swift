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
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let width: Int
    let height: Int
    private let queue = DispatchQueue(label: "touchdeck.screen")
    private let onPacket: @Sendable (VideoPacket) -> Void
    private let onStop: @Sendable () -> Void
    private var stream: SCStream?
    // 아래는 queue에서만 만진다
    private var encoder: VTCompressionSession?
    private var forceKeyframe = true
    /// 화면이 멈춰 있으면 새 프레임이 안 온다. 키프레임을 달라고 하면 마지막 화면을 다시 압축한다
    private var lastFrame: CVPixelBuffer?

    init(width: Int, height: Int, onPacket: @escaping @Sendable (VideoPacket) -> Void, onStop: @escaping @Sendable () -> Void) {
        self.width = width
        self.height = height
        self.onPacket = onPacket
        self.onStop = onStop
    }

    enum StartError: Error { case noDisplay }

    /// 모니터를 찾아 크기를 정하고 찍기 시작한다. SCDisplay는 여러 스레드에 넘길 수 없어서 찾기부터 여기서 한다.
    static func start(displayId: CGDirectDisplayID, maxSide: Int, onPacket: @escaping @Sendable (VideoPacket) -> Void,
                      onStop: @escaping @Sendable () -> Void) async throws -> ScreenStreamer {
        guard let display = try await DisplayCatalog.displays().first(where: { $0.displayID == displayId }) else {
            throw StartError.noDisplay
        }
        let size = ScreenGeometry.fit(width: display.width, height: display.height, maxSide: maxSide)
        let streamer = ScreenStreamer(width: size.width, height: size.height, onPacket: onPacket, onStop: onStop)
        try await streamer.start(display: display)
        return streamer
    }

    private func start(display: SCDisplay) async throws {
        try queue.sync { try makeEncoder() }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = true
        config.queueDepth = 4
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
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
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
        // 글자가 많은 화면이라 넉넉하게: 1920×804면 약 7Mbps
        let bitRate = Int(Double(width * height) * 30 * 0.15)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        encoder = session
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
