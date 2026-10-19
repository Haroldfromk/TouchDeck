/// 맥 화면을 보면서 보내는 특수 키. 클로드 코드 터미널에서 자주 쓰는 것만.
public enum RemoteKey: String, Codable, CaseIterable, Sendable {
    case escape, tab, shiftTab, up, down, left, right, delete, enter, controlC
}

/// 입력칸에 쓴 글을 맥으로 보내기 전에 다듬고 나눈다. 아이패드와 맥 양쪽에서 같은 규칙을 쓴다.
public enum TextInput {
    public static let maxCharacters = 2000
    /// 맥 키보드 이벤트 하나에 실을 수 있는 글자 수가 적다
    public static let maxChunkUTF16 = 20

    /// 줄바꿈과 탭은 띄어쓰기로 (중간에 엔터가 눌려 명령이 실행되지 않게). 2,000글자에서 자른다.
    /// 글자(Character) 단위로 자르니 이모지나 조합 글자가 반쪽 나지 않는다
    public static func clean(_ text: String) -> String {
        var out = ""
        for character in text {
            out.append(character == "\n" || character == "\r\n" || character == "\r" || character == "\t" ? " " : character)
            if out.count == maxCharacters { break }
        }
        return out
    }

    /// UTF-16 20개 이하 묶음으로 나눈다. 글자 하나를 두 묶음에 걸치게 쪼개지 않는다
    public static func chunks(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if !current.isEmpty && current.utf16.count + character.utf16.count > maxChunkUTF16 {
                result.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
