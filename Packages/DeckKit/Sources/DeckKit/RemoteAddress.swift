import Foundation

/// 밖에서 붙을 맥 주소(Tailscale이 맥에 붙인 이름이나 100.x.x.x).
/// 사람이 친 주소를 다듬고, WebSocket으로 붙을 URL을 만든다.
public enum RemoteAddress {
    public static let port = 52801

    /// 앞뒤 공백, `ws://` 같은 앞부분, 끝의 `/`와 `:포트`를 뗀다. 비었거나 공백이 섞이면 nil
    public static func clean(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["ws://", "wss://", "http://", "https://"] where text.lowercased().hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        while text.hasSuffix("/") { text.removeLast() }
        if let colon = text.lastIndex(of: ":"), !text[text.index(after: colon)...].isEmpty,
           text[text.index(after: colon)...].allSatisfy(\.isNumber) {
            text = String(text[..<colon])
        }
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        return text
    }

    /// `host:port`로는 WebSocket이 안 열려서(첫 HTTP 인사에 넣을 주소가 필요하다) URL로 붙는다
    public static func url(host: String) -> URL? {
        URL(string: "ws://\(host):\(port)/")
    }
}
