/// 연결할 때 서로 알려 주는 기능 번호. 번호를 안 보내는 예전 앱과 ESP32 보드는 1로 본다.
/// 1: 버튼, 볼륨, 키패드, 화면 보기(1, 2차)   2: 글자 입력(typeText, pressKey)   3: 키패드 기호
public enum DeckProtocol {
    public static let legacy = 1
    public static let textInput = 2
    public static let symbolKeys = 3
    public static let current = symbolKeys
}

public enum DeckConstants {
    public static let serviceType = "_touchdeck._tcp"
    public static let columns = 4
    public static let rows = 3
    public static let slotsPerPage = 12
}
