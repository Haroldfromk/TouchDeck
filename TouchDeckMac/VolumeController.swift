import Foundation

/// 맥 출력 소리 크기. AppleScript의 `volume settings`를 쓴다 (따로 권한이 필요 없다).
enum VolumeController {
    static func get() -> (value: Int, muted: Bool, available: Bool) {
        // 예: "output volume:50, input volume:75, alert volume:100, output muted:false"
        let text = osascript("get volume settings") ?? ""
        return parse(text)
    }

    static func set(_ value: Int) {
        let clamped = min(max(value, 0), 100)
        var script = "set volume output volume \(clamped)"
        if clamped > 0 { script += "\nset volume without output muted" }
        _ = osascript(script)
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

    private static func osascript(_ script: String) -> String? {
        let pipe = Pipe()
        guard (try? runProcess("/usr/bin/osascript", ["-e", script], output: pipe)) == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
