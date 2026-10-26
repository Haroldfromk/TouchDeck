/// 연결할 때 서로 알려 주는 기능 번호. 번호를 안 보내는 예전 앱과 ESP32 보드는 1로 본다.
/// 1: 버튼, 볼륨, 키패드, 화면 보기(1, 2차)   2: 글자 입력(typeText, pressKey)   3: 키패드 기호   4: 맥 잠금 풀기   5: 맥이 정한 길   6: 맥 잠그기   7: 버튼 옮기기
public enum DeckProtocol {
    public static let legacy = 1
    public static let textInput = 2
    public static let symbolKeys = 3
    public static let unlock = 4
    public static let routeFromMac = 5
    public static let lockMac = 6
    public static let moveButton = 7
    public static let current = moveButton
}

public enum DeckConstants {
    public static let serviceType = "_touchdeck._tcp"
    public static let columns = 4
    public static let rows = 3
    public static let slotsPerPage = 12
}
