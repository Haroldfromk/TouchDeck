import AVFoundation
import CoreMedia
import DeckKit
import UIKit

/// 맥에서 온 H.264 묶음을 하드웨어로 풀어서 바로 그린다(AVSampleBufferDisplayLayer).
/// 시간 정보 없이 "도착하면 바로 보여주기"로 넣어서 지연이 쌓이지 않게 한다.
@MainActor
final class VideoRenderer {
    let layer = AVSampleBufferDisplayLayer()
    private var format: CMVideoFormatDescription?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
    }

    /// 그렸으면 true. 키프레임이 아직 없거나 풀기에 실패했으면 false (맥에 키프레임을 달라고 해야 한다)
    func enqueue(_ packet: VideoPacket) -> Bool {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
            format = nil
        }
        if packet.keyframe, let made = Self.makeFormat(packet.parameterSets) {
            format = made
        }
        guard let format, let sample = Self.makeSample(packet.frame, format: format) else { return false }
        renderer.enqueue(sample)
        return renderer.status != .failed
    }

    /// 화면 보기를 멈추거나 모니터를 바꿀 때. 남은 화면을 지운다
    func reset() {
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        format = nil
    }

    private static func makeFormat(_ sets: [Data]) -> CMVideoFormatDescription? {
        guard sets.count >= 2 else { return nil }
        let buffers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        var format: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
            parameterSetPointers: buffers.map { UnsafePointer($0) }, parameterSetSizes: sets.map(\.count),
            nalUnitHeaderLength: 4, formatDescriptionOut: &format)
        return status == noErr ? format : nil
    }

    private static func makeSample(_ frame: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: frame.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = frame.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: frame.count)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = frame.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
