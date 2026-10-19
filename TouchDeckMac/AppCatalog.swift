import AppKit
import DeckKit
import Foundation

/// 맥에 설치된 앱 목록과 아이콘.
enum AppCatalog {
    static let iconSize = 96

    static var folders: [URL] {
        [
            URL(filePath: "/Applications"),
            URL(filePath: "/Applications/Utilities"),
            URL(filePath: "/System/Applications"),
            URL(filePath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
    }

    static func scan() -> [AppInfo] {
        var seen = Set<String>()
        var apps: [AppInfo] = []
        for folder in folders {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier,
                      seen.insert(bundleId).inserted else { continue }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                apps.append(AppInfo(name: name, bundleId: bundleId, icon: iconPNG(for: url)?.base64EncodedString() ?? ""))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 앱 아이콘을 96×96 PNG로. 아이패드 버튼(약 48pt, 레티나 2배)에서 선명하다.
    static func iconPNG(for appURL: URL) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: iconSize, pixelsHigh: iconSize,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
