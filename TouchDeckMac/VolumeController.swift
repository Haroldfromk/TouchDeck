import AppKit
import CoreAudio
import Foundation

/// 맥 출력 소리 크기를 읽고 정한다. 두 길이 있다.
/// - macOS가 아는 장치(맥북 스피커, 에어팟 등): AppleScript의 volume settings
/// - DisplayPort/HDMI 모니터: macOS는 모른다. BetterDisplay가 켜져 있으면 그 모니터에 DDC로 묻고 정한다
/// 둘 다 안 되면 available == false. 그때 아이패드는 볼륨 키 신호(끄는 띠)로 조절한다.
enum VolumeController {
    enum Source: Equatable {
        case system
        case betterDisplay(name: String)
        case none
    }

    static let betterDisplayPath = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
    static let betterDisplayBundleId = "pro.betterdisplay.BetterDisplay"

    static func get() -> (value: Int, muted: Bool, available: Bool) {
        // 예: "output volume:50, input volume:75, alert volume:100, output muted:false"
        let system = parse(osascript("get volume settings") ?? "")
        switch source(systemAvailable: system.available) {
        case .system:
            return system
        case .betterDisplay(let name):
            let raw = betterDisplay(["get", "-name=\(name)", "-volume"])
            guard let value = raw.flatMap(parseBetterDisplayVolume) else {
                // 게이지가 가끔 끄는 띠로 바뀌던 원인을 찾으려고 어디서 실패했는지 남긴다
                print("[volume] BetterDisplay read failed for \(name):", raw.map { "output \($0.prefix(60))" } ?? "process failed")
                return (0, false, false)
            }
            let muted = betterDisplay(["get", "-name=\(name)", "-mute"])?.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
            return (value, muted, true)
        case .none:
            print("[volume] no source: system unavailable, output \(defaultOutputName() ?? "nil")")
            return (0, false, false)
        }
    }

    static func set(_ value: Int) {
        let clamped = min(max(value, 0), 100)
        let systemAvailable = parse(osascript("get volume settings") ?? "").available
        switch source(systemAvailable: systemAvailable) {
        case .system:
            var script = "set volume output volume \(clamped)"
            if clamped > 0 { script += "\nset volume without output muted" }
            _ = osascript(script)
        case .betterDisplay(let name):
            _ = betterDisplay(["set", "-name=\(name)", "-volume=\(betterDisplayVolumeArgument(clamped))"])
        case .none:
            break
        }
    }

    // MARK: - 판단 (테스트 대상)

    static func chooseSource(systemAvailable: Bool, outputName: String?, betterDisplayRunning: Bool) -> Source {
        if systemAvailable { return .system }
        if let outputName, betterDisplayRunning { return .betterDisplay(name: outputName) }
        return .none
    }

    /// BetterDisplay는 0~1 값을 돌려준다. "Failed." 같은 건 nil
    static func parseBetterDisplayVolume(_ text: String) -> Int? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    static func betterDisplayVolumeArgument(_ value: Int) -> String {
        String(format: "%.2f", Double(min(max(value, 0), 100)) / 100)
    }

    static func parse(_ text: String) -> (value: Int, muted: Bool, available: Bool) {
        var value: Int?
        var muted = false
        for part in text.split(separator: ",") {
            let pair = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            if pair[0] == "output volume" { value = Int(pair[1]) }
            if pair[0] == "output muted" { muted = pair[1] == "true" }
        }
        // 모니터(DisplayPort/HDMI)처럼 소리 크기가 없는 장치는 "missing value"
        return (value ?? 0, muted, value != nil)
    }

    // MARK: - 바깥과 닿는 부분

    private static func source(systemAvailable: Bool) -> Source {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: betterDisplayBundleId).isEmpty
        return chooseSource(systemAvailable: systemAvailable, outputName: defaultOutputName(), betterDisplayRunning: running)
    }

    /// 지금 소리가 나가는 장치 이름 (예: "LG ULTRAWIDE"). BetterDisplay의 디스플레이 이름과 같다.
    static func defaultOutputName() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    /// 켜져 있는 BetterDisplay에게 명령을 보낸다 (앱 안의 실행 파일이 CLI 역할을 한다). 약 0.2초
    private static func betterDisplay(_ arguments: [String]) -> String? {
        guard FileManager.default.fileExists(atPath: betterDisplayPath) else { return nil }
        let pipe = Pipe()
        guard (try? runProcess(betterDisplayPath, arguments, output: pipe)) == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func osascript(_ script: String) -> String? {
        let pipe = Pipe()
        guard (try? runProcess("/usr/bin/osascript", ["-e", script], output: pipe)) == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
