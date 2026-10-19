# TouchDeck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이패드(가로)/아이폰 화면 버튼을 탭하면 맥에서 앱 실행 / Alacritty 명령 실행 / 새 Alacritty 창 / 볼륨 조절이 되는 스트림덱을 만든다.

**Architecture:** 맥 메뉴바 앱이 `NWListener`로 WebSocket 서버를 열고 Bonjour(`_touchdeck._tcp`)로 광고한다. iOS 앱은 `NWBrowser`로 찾아 `NWConnection`(WebSocket)으로 붙고, JSON 텍스트 메시지를 주고받는다. 메시지 / 배치 / 페어링 / 명령 줄 만들기 같은 순수 로직은 로컬 Swift Package `DeckKit`에 두고 `swift test`로 검증한다.

**Tech Stack:** Swift 6, SwiftUI, Network.framework, CryptoKit, AppKit(NSWorkspace), Swift Testing, xcodegen

**Spec:** `docs/superpowers/specs/2026-10-19-touchdeck-design.md`

## Global Constraints

- 최소 버전: iOS/iPadOS 26, macOS 26. Xcode 27
- 외부 라이브러리 없음 (애플 프레임워크만)
- Bonjour 서비스 타입: `_touchdeck._tcp`
- 한 페이지 12칸 (4열 × 3줄)
- 맥 앱: 샌드박스 끔, Dock 아이콘 없음(`LSUIElement`), `MenuBarExtra`
- 설정 파일: `~/Library/Application Support/TouchDeck/config.json`
- Alacritty 위치: `/Applications/Alacritty.app`
- iOS Info.plist: `NSLocalNetworkUsageDescription`, `NSBonjourServices = [_touchdeck._tcp]`
- 서명 설정은 넣지 않는다 (해롤드가 나중에). 맥은 로컬 실행용 ad-hoc(`CODE_SIGN_IDENTITY = "-"`)
- 메시지는 ESP32도 읽을 수 있는 단순 JSON 텍스트. 최상위에 `"type"` 문자열
- 커밋 메시지에 Co-Authored-By 줄을 넣지 않는다
- iOS Simulator MCP 도구 금지. 시뮬레이터는 `xcrun simctl`만
- 아이패드 화면 전체는 스크롤되지 않는다 (페이지는 옆으로 넘기기)

## Review Focus

1. 별칭 명령의 따옴표/공백 (`git commit -m "a b"`): Alacritty에 넘길 인자가 깨지지 않아야 한다 → Task 2 `AlacrittyCommandTests`
2. 존재하지 않는 폴더 / 찾을 수 없는 명령: "실행했음"이 아니라 이유가 담긴 실패 → Task 4 `ActionRunnerTests`
3. 잘못된 페어링 숫자 반복 입력: 5번 틀리면 숫자를 새로 만든다 (무한 추측 차단) → Task 2 `PairingAuthorityTests`
4. 허락 취소된 기기가 예전 토큰으로 다시 붙기: 거절되고 다시 페어링을 요구해야 한다 → Task 2 `PairingAuthorityTests`
5. 맥 앱이 꺼졌다 켜짐 / 와이파이 끊김: 아이패드가 상태를 분명히 보여주고 다시 찾아 붙는다 → Task 6 수동 확인 단계

---

## File Structure

```
TouchDeck/
├── project.yml                         xcodegen: TouchDeck(iOS), TouchDeckMac(macOS), DeckKit 패키지
├── Packages/DeckKit/
│   ├── Package.swift
│   ├── Sources/DeckKit/
│   │   ├── DeckConstants.swift         서비스 타입, 칸 수
│   │   ├── DeckLayout.swift            DeckButton, ButtonAction, DeckPage, DeckLayout(+편집)
│   │   ├── Messages.swift              ClientMessage, ServerMessage, AppInfo (+JSON 코덱)
│   │   ├── Pairing.swift               PairingAuthority, TrustedDevice, signature(token:nonce:)
│   │   ├── AlacrittyCommand.swift      Alacritty 실행 인자, 첫 단어 뽑기
│   │   └── WebSocketChannel.swift      NWConnection 위 텍스트 메시지 송수신 (양쪽 공용)
│   └── Tests/DeckKitTests/             위 각 파일별 테스트
├── TouchDeckMac/
│   ├── TouchDeckMacApp.swift           MenuBarExtra 진입점
│   ├── MenuContent.swift               메뉴 UI
│   ├── DeckServer.swift                NWListener, 접속별 세션, 방송
│   ├── ClientSession.swift             한 기기 접속의 핸드셰이크 상태
│   ├── ConfigStore.swift               config.json 읽기/쓰기
│   ├── AppCatalog.swift                설치 앱 목록 + 아이콘 PNG
│   ├── ActionRunner.swift              앱 열기 / Alacritty / 사전 확인
│   ├── VolumeController.swift          osascript 볼륨
│   └── Info.plist
└── TouchDeck/                          iOS 유니버설
    ├── TouchDeckApp.swift
    ├── DeckClient.swift                찾기/연결/핸드셰이크/상태 (@Observable)
    ├── KeychainStore.swift             deviceId, token
    ├── Views/DeckView.swift            B안 배치 (가로) + 세로 배치
    ├── Views/ButtonTile.swift
    ├── Views/VolumeSlider.swift
    ├── Views/EditSheet.swift           종류 선택, 앱 고르기, 명령 입력
    ├── Views/PairingView.swift         4자리 입력
    ├── Views/ConnectionStatusView.swift
    └── Info.plist
```

---

### Task 1: 저장소와 DeckKit 배치 모델

**Files:**
- Create: `project.yml`, `.gitignore`, `Packages/DeckKit/Package.swift`, `Sources/DeckKit/DeckConstants.swift`, `Sources/DeckKit/DeckLayout.swift`
- Test: `Packages/DeckKit/Tests/DeckKitTests/DeckLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum DeckConstants { static let serviceType = "_touchdeck._tcp"; static let columns = 4; static let rows = 3; static let slotsPerPage = 12 }`
  - `enum ButtonAction: Codable, Equatable, Sendable { case app(bundleId: String); case command(command: String, directory: String?); case terminal(directory: String?) }` JSON: `{"kind":"app","bundleId":…}` / `{"kind":"command","command":…,"directory":…}` / `{"kind":"terminal","directory":…}`
  - `struct DeckButton: Codable, Equatable, Sendable { var label: String; var action: ButtonAction }`
  - `struct DeckPage: Codable, Equatable, Sendable { var buttons: [DeckButton?] }` (항상 12개)
  - `struct DeckLayout: Codable, Equatable, Sendable { var pages: [DeckPage]; static let empty; mutating func set(_ button: DeckButton, page: Int, index: Int) throws; mutating func clear(page: Int, index: Int) throws }`
  - `enum LayoutError: Error { case outOfRange }`
- 페이지 규칙 (Claude 결정): 마지막 페이지에 버튼이 하나라도 있으면 끝에 빈 페이지를 하나 붙인다. 끝에 빈 페이지가 둘 이상이면 하나만 남긴다. 항상 최소 1페이지. `set`/`clear` 뒤에 이 규칙을 적용한다

- [ ] **Step 1:** `git init`, `.gitignore`(`.build/`, `*.xcodeproj/`, `xcuserdata/`, `.superpowers/`, `DerivedData/`). `Package.swift`: `swift-tools-version:6.2`, platforms `.iOS(.v26), .macOS(.v26)`, library `DeckKit`, testTarget `DeckKitTests`
- [ ] **Step 2: 실패하는 테스트**

```swift
@Test func emptyLayoutHasOnePageOfTwelve() {
    #expect(DeckLayout.empty.pages.count == 1)
    #expect(DeckLayout.empty.pages[0].buttons.count == 12)
}
@Test func settingOnLastPageAppendsEmptyPage() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "Xcode", action: .app(bundleId: "com.apple.dt.Xcode")), page: 0, index: 3)
    #expect(l.pages.count == 2)
    #expect(l.pages[0].buttons[3]?.label == "Xcode")
}
@Test func clearingTrimsTrailingEmptyPages() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "a", action: .terminal(directory: nil)), page: 0, index: 0)
    try l.set(DeckButton(label: "b", action: .terminal(directory: nil)), page: 1, index: 0)
    try l.clear(page: 1, index: 0)
    #expect(l.pages.count == 2)
}
@Test func outOfRangeThrows() {
    var l = DeckLayout.empty
    #expect(throws: LayoutError.outOfRange) { try l.set(DeckButton(label: "x", action: .terminal(directory: nil)), page: 0, index: 12) }
    #expect(throws: LayoutError.outOfRange) { try l.clear(page: 5, index: 0) }
}
@Test func actionJSONShape() throws {
    let data = try JSONEncoder().encode(ButtonAction.command(command: "blogrun", directory: "~/Documents/Workspace/blog"))
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: String]
    #expect(obj == ["kind": "command", "command": "blogrun", "directory": "~/Documents/Workspace/blog"])
}
```

- [ ] **Step 3:** `cd Packages/DeckKit && swift test` → FAIL (타입 없음)
- [ ] **Step 4:** 구현. `ButtonAction`은 `kind` 키로 수동 Codable. `directory`가 nil이면 키 생략
- [ ] **Step 5:** `swift test` → PASS
- [ ] **Step 6:** `project.yml` 작성 (iOS 앱 `TouchDeck`, 맥 앱 `TouchDeckMac`, 둘 다 `DeckKit` 의존. bundle id `com.harold.TouchDeck`, `com.harold.TouchDeckMac`. iOS `TARGETED_DEVICE_FAMILY = "1,2"`, 맥 `ENABLE_APP_SANDBOX = NO`, `LSUIElement = YES`). 빈 `@main` 앱 두 개로 `xcodegen generate` 후 두 타깃 `xcodebuild build` 성공 확인 (iOS는 `-destination 'generic/platform=iOS Simulator'`)
- [ ] **Step 7:** Commit `feat: DeckKit 배치 모델과 프로젝트 뼈대`

---

### Task 2: 메시지, 페어링, Alacritty 명령 (DeckKit 순수 로직)

**Files:**
- Create: `Sources/DeckKit/Messages.swift`, `Pairing.swift`, `AlacrittyCommand.swift`
- Test: `MessagesTests.swift`, `PairingAuthorityTests.swift`, `AlacrittyCommandTests.swift`

**Interfaces:**
- Consumes: Task 1 `DeckLayout`, `DeckButton`
- Produces:
  - `struct AppInfo: Codable, Equatable, Sendable { var name: String; var bundleId: String; var icon: String /* base64 PNG */ }`
  - `enum ClientMessage: Equatable, Sendable { case hello(deviceId: String, deviceName: String); case pair(code: String); case auth(signature: String); case press(page: Int, index: Int); case getApps; case setButton(page: Int, index: Int, button: DeckButton); case clearButton(page: Int, index: Int); case setVolume(Int) }`
  - `enum ServerMessage: Equatable, Sendable { case needPairing; case pairingFailed(remaining: Int); case paired(token: String); case challenge(nonce: String); case authorized; case unauthorized; case layout(DeckLayout); case apps([AppInfo]); case pressResult(page: Int, index: Int, ok: Bool, message: String?); case volume(value: Int, muted: Bool) }`
  - 둘 다 `func encoded() throws -> String`, `static func decode(_ text: String) throws -> Self`. JSON 키는 스펙 4장 이름 그대로 (`type` 값 = case 이름, `setVolume`은 `{"type":"setVolume","value":55}`)
  - `func pairingSignature(token: String, nonce: String) -> String` = HMAC-SHA256(key: token UTF8, data: nonce UTF8)의 소문자 hex
  - `struct TrustedDevice: Codable, Equatable, Sendable { var id: String; var name: String; var token: String }`
  - `struct PairingAuthority: Sendable` (맥 쪽 판정, 상태를 가진 값 타입)
    - `init(trusted: [TrustedDevice], random: @Sendable () -> UInt32 = { .random(in: 0...UInt32.max) })`
    - `var trusted: [TrustedDevice] { get }`, `var currentCode: String? { get }` (메뉴에 보여줄 4자리)
    - `mutating func beginPairing(deviceId: String, deviceName: String) -> String` 새 4자리 코드("0000"~"9999", 앞자리 0 유지)
    - `mutating func submit(code: String, deviceId: String) -> PairingOutcome` `enum PairingOutcome: Equatable { case paired(token: String); case wrong(remaining: Int); case regenerated(newCode: String) }` 5번 틀리면 `.regenerated`, 시도 횟수 초기화
    - `func verify(deviceId: String, nonce: String, signature: String) -> Bool`
    - `mutating func revoke(deviceId: String)`
  - `enum AlacrittyCommand { static let appPath = "/Applications/Alacritty.app"; static func openArguments(command: String?, directory: String?) -> [String]; static func firstWord(of command: String) -> String?; static func expandTilde(_ path: String) -> String }`
    - `command`가 있으면: `["-na", appPath, "--args", "--working-directory", dir, "-e", "/bin/zsh", "-ic", "\(command); exec zsh"]`
    - `command`가 nil(새 창): `["-na", appPath, "--args", "--working-directory", dir]`
    - `dir`은 `directory`를 `expandTilde`한 값, nil이면 홈
    - `/usr/bin/open`의 인자 배열이라 셸 따옴표 처리가 필요 없다 (명령 문자열은 zsh `-c` 인자 하나로 통째로 들어감)

- [ ] **Step 1: 실패하는 테스트**

```swift
// MessagesTests
@Test func pressRoundTrip() throws {
    let text = try ClientMessage.press(page: 0, index: 3).encoded()
    #expect(try ClientMessage.decode(text) == .press(page: 0, index: 3))
    #expect(text.contains("\"type\":\"press\""))
}
@Test func setButtonRoundTrip() throws {
    let m = ClientMessage.setButton(page: 1, index: 2, button: DeckButton(label: "blogrun", action: .command(command: "blogrun", directory: "~/Documents/Workspace/blog")))
    #expect(try ClientMessage.decode(m.encoded()) == m)
}
@Test func layoutRoundTripKeepsNullSlots() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "X", action: .app(bundleId: "com.apple.dt.Xcode")), page: 0, index: 5)
    #expect(try ServerMessage.decode(ServerMessage.layout(l).encoded()) == .layout(l))
}
@Test func unknownTypeThrows() { #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"type":"nope"}"#) } }

// PairingAuthorityTests
@Test func correctCodePairsAndTrusts() {
    var a = PairingAuthority(trusted: [], random: { 4821 })
    let code = a.beginPairing(deviceId: "ipad", deviceName: "iPad")
    #expect(code == "4821")
    guard case .paired(let token) = a.submit(code: "4821", deviceId: "ipad") else { Issue.record(); return }
    #expect(a.trusted.map(\.id) == ["ipad"])
    #expect(a.verify(deviceId: "ipad", nonce: "n1", signature: pairingSignature(token: token, nonce: "n1")))
    #expect(a.currentCode == nil)
}
@Test func codeKeepsLeadingZeros() { var a = PairingAuthority(trusted: [], random: { 42 }); #expect(a.beginPairing(deviceId: "d", deviceName: "d") == "0042") }
@Test func fiveWrongCodesRegenerate() {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    for r in stride(from: 4, through: 1, by: -1) { #expect(a.submit(code: "9999", deviceId: "d") == .wrong(remaining: r)) }
    guard case .regenerated = a.submit(code: "9999", deviceId: "d") else { Issue.record(); return }
}
@Test func revokedDeviceFailsVerify() {
    var a = PairingAuthority(trusted: [TrustedDevice(id: "d", name: "d", token: "t")])
    a.revoke(deviceId: "d")
    #expect(!a.verify(deviceId: "d", nonce: "n", signature: pairingSignature(token: "t", nonce: "n")))
}
@Test func wrongSignatureFails() {
    let a = PairingAuthority(trusted: [TrustedDevice(id: "d", name: "d", token: "t")])
    #expect(!a.verify(deviceId: "d", nonce: "n", signature: pairingSignature(token: "other", nonce: "n")))
}

// AlacrittyCommandTests
@Test func commandArgumentsKeepQuotesIntact() {
    let args = AlacrittyCommand.openArguments(command: #"git commit -m "a b""#, directory: "/tmp")
    #expect(args == ["-na", "/Applications/Alacritty.app", "--args", "--working-directory", "/tmp", "-e", "/bin/zsh", "-ic", #"git commit -m "a b"; exec zsh"#])
}
@Test func newWindowArgumentsDefaultToHome() {
    #expect(AlacrittyCommand.openArguments(command: nil, directory: nil) == ["-na", "/Applications/Alacritty.app", "--args", "--working-directory", NSHomeDirectory()])
}
@Test func tildeExpands() { #expect(AlacrittyCommand.expandTilde("~/Documents") == NSHomeDirectory() + "/Documents") }
@Test func firstWordSkipsLeadingSpaces() { #expect(AlacrittyCommand.firstWord(of: "  blogrun --x") == "blogrun"); #expect(AlacrittyCommand.firstWord(of: "   ") == nil) }
```

- [ ] **Step 2:** `swift test` → FAIL
- [ ] **Step 3:** 구현. 메시지 코덱은 `type` 키로 분기하는 수동 Codable. HMAC은 CryptoKit `HMAC<SHA256>`. 토큰은 32바이트 `SystemRandomNumberGenerator` → base64. 코드는 `random() % 10000`을 4자리 zero-pad
- [ ] **Step 4:** `swift test` → PASS
- [ ] **Step 5:** Commit `feat: 메시지 코덱, 페어링 판정, Alacritty 인자`

---

### Task 3: WebSocket 채널과 맥 서버 (핸드셰이크까지)

**Files:**
- Create: `Sources/DeckKit/WebSocketChannel.swift`, `TouchDeckMac/DeckServer.swift`, `TouchDeckMac/ClientSession.swift`, `TouchDeckMac/ConfigStore.swift`
- Test: `Packages/DeckKit/Tests/DeckKitTests/WebSocketChannelTests.swift`

**Interfaces:**
- Consumes: Task 2 메시지, `PairingAuthority`
- Produces:
  - `enum DeckNetwork { static func parameters() -> NWParameters }` TCP + `NWProtocolWebSocket.Options`(autoReplyPing = true, maximumMessageSize = 16MB) 를 applicationProtocols 맨 앞에. 서버/클라이언트 공용
  - `final class WebSocketChannel: @unchecked Sendable { init(connection: NWConnection); func start(queue: DispatchQueue); func send(_ text: String); var onText: (@Sendable (String) -> Void)?; var onState: (@Sendable (NWConnection.State) -> Void)?; func cancel() }` 텍스트 opcode 메시지만. 받기는 `receiveMessage` 반복
  - `struct DeckConfig: Codable { var layout: DeckLayout; var trustedDevices: [TrustedDevice] }`, `final class ConfigStore { init(url: URL = 기본 경로); func load() -> DeckConfig; func save(_: DeckConfig) throws }` 파일 없거나 깨졌으면 `layout: .empty, trustedDevices: []`
  - `@MainActor @Observable final class DeckServer { var connectedDevices: [String]; var pairingCode: String?; var trusted: [TrustedDevice]; var status: String; func start(); func revoke(deviceId:); func broadcastLayout() }`
  - 핸드셰이크 (ClientSession): `hello` → 신뢰 기기면 `challenge(nonce)` → `auth(signature)` 검증 → `authorized` + `layout` + `apps` + `volume` / 아니면 `needPairing` (메뉴에 코드 표시) → `pair(code)` → `paired(token)` + 위와 같은 초기 메시지. 인증 전에 온 그 밖의 메시지에는 `unauthorized`만 답하고 실행하지 않는다

- [ ] **Step 1: 실패하는 테스트** (로컬 루프백으로 실제 NWListener ↔ NWConnection)

```swift
@Test func echoesTextOverLoopback() async throws {
    // NWListener(using: DeckNetwork.parameters(), on: .any) 시작, 받은 텍스트를 그대로 돌려주는 서버
    // NWConnection(host: "127.0.0.1", port: listener.port!, using: DeckNetwork.parameters())
    // 클라이언트 WebSocketChannel.send("{\"type\":\"getApps\"}") → onText로 같은 문자열을 5초 안에 받는다
}
```

- [ ] **Step 2:** `swift test --filter WebSocketChannelTests` → FAIL
- [ ] **Step 3:** `WebSocketChannel`, `DeckNetwork` 구현
- [ ] **Step 4:** PASS 확인
- [ ] **Step 5:** `ConfigStore`, `ClientSession`, `DeckServer` 구현. 리스너 `service = NWListener.Service(type: DeckConstants.serviceType)` (이름은 맥 컴퓨터 이름이 기본). 상태 변화는 `print`로도 남긴다 (블로그 캡처용). 실행 동작(Task 4)은 아직 `pressResult(ok: false, message: "준비 중")`
- [ ] **Step 6:** 맥 앱 빌드, 실행 후 `dns-sd -B _touchdeck._tcp` 로 광고가 보이는지 확인. Expected: `Add ... _touchdeck._tcp.` 한 줄
- [ ] **Step 7:** Commit `feat: NWListener WebSocket 서버와 페어링 핸드셰이크`

---

### Task 4: 맥 실행기 (앱 목록, 앱 열기, Alacritty, 볼륨)

**Files:**
- Create: `TouchDeckMac/AppCatalog.swift`, `ActionRunner.swift`, `VolumeController.swift`, `MenuContent.swift`, `TouchDeckMacApp.swift`
- Test: 맥 앱 단위 테스트 타깃 `TouchDeckMacTests/ActionRunnerTests.swift` (project.yml에 추가)

**Interfaces:**
- Consumes: Task 2 `AlacrittyCommand`, Task 3 `DeckServer`
- Produces:
  - `enum AppCatalog { static func scan() -> [AppInfo] }` 스펙 3장의 네 폴더, 바로 아래 `.app`만 (재귀는 `/System/Applications/Utilities` 한 단계까지). 이름순, bundle id 중복 제거. 아이콘 96×96 PNG base64
  - `struct ActionRunner { var commandExists: (String) async -> Bool; var directoryExists: (String) -> Bool; var openApp: (String) async throws -> Void; var runOpen: ([String]) throws -> Void; func run(_ action: ButtonAction) async -> (ok: Bool, message: String?); static let live; static func fake() -> ActionRunner /* 전부 성공하는 가짜 */ }`
    - `.app`: `urlForApplication` 없으면 `(false, "앱을 찾을 수 없음: <bundleId>")`
    - `.command`: 폴더 없음 → `(false, "폴더 없음: <경로>")`, `firstWord` 를 `zsh -ic 'whence -- <word>'` 종료 코드로 확인해 없으면 `(false, "<word>을(를) 찾을 수 없음")`, 통과하면 `/usr/bin/open` + `AlacrittyCommand.openArguments`
    - `.terminal`: 폴더 확인 후 `openArguments(command: nil, …)`
    - Alacritty가 없으면 `(false, "Alacritty가 설치되어 있지 않음")`
  - `enum VolumeController { static func get() -> (value: Int, muted: Bool); static func set(_ value: Int) }` (`/usr/bin/osascript`, 0~100으로 자름. 0이 아니면 음소거 해제)
  - 메뉴: 서버 상태, 페어링 코드(있을 때 크게), 연결된 기기, 허락한 기기 목록 + "허락 취소", 종료

- [ ] **Step 1: 실패하는 테스트** (`ActionRunner`에 가짜 클로저 주입)

```swift
@Test func missingDirectoryFailsWithReason() async {
    var r = ActionRunner.fake(); r.directoryExists = { _ in false }
    let out = await r.run(.command(command: "blogrun", directory: "~/nope"))
    #expect(out.ok == false); #expect(out.message == "폴더 없음: \(NSHomeDirectory())/nope")
}
@Test func unknownCommandFailsWithReason() async {
    var r = ActionRunner.fake(); r.commandExists = { _ in false }
    let out = await r.run(.command(command: "blogrn", directory: nil))
    #expect(out.ok == false); #expect(out.message == "blogrn을(를) 찾을 수 없음")
}
@Test func validCommandOpensAlacrittyWithArguments() async {
    var captured: [String] = []
    var r = ActionRunner.fake(); r.runOpen = { captured = $0 }
    let out = await r.run(.command(command: "blogrun", directory: "/tmp"))
    #expect(out.ok); #expect(captured == AlacrittyCommand.openArguments(command: "blogrun", directory: "/tmp"))
}
```

- [ ] **Step 2:** `xcodebuild test -scheme TouchDeckMac` → FAIL
- [ ] **Step 3:** 구현하고 `DeckServer`의 `press` / `getApps` / `setButton` / `clearButton` / `setVolume` 처리를 연결. 설정 바뀌면 저장 후 모든 인증된 세션에 `layout` 방송. 볼륨 바뀌면 `volume` 방송
- [ ] **Step 4:** PASS 확인
- [ ] **Step 5:** 실제 확인: 맥 앱 실행 → 작은 테스트 클라이언트(`swift` 스크립트 또는 테스트) 대신 Task 6에서 시뮬레이터로 확인. 여기서는 `zsh -ic 'whence -- blogrun'`이 0으로 끝나는지 터미널에서 한 번 확인
- [ ] **Step 6:** Commit `feat: 맥 실행기, 앱 목록, 볼륨, 메뉴`

---

### Task 5: iOS 클라이언트 (찾기, 연결, 페어링, 상태)

**Files:**
- Create: `TouchDeck/DeckClient.swift`, `KeychainStore.swift`, `TouchDeckApp.swift`, `Info.plist` 항목(project.yml)

**Interfaces:**
- Consumes: `DeckNetwork`, `WebSocketChannel`, 메시지, `pairingSignature`
- Produces:
  - `@MainActor @Observable final class DeckClient { enum Phase: Equatable { case searching, connecting(String), needsPairing(String), pairingFailed(remaining: Int), connected(String), localNetworkDenied }; var phase: Phase; var layout: DeckLayout; var apps: [String: AppInfo]; var icons: [String: UIImage]; var volume: Int; var muted: Bool; var lastResult: (page: Int, index: Int, ok: Bool, message: String?)?; func start(); func press(page:index:); func submitPairing(code:); func setButton(_:page:index:); func clearButton(page:index:); func setVolume(_:) }`
  - `enum KeychainStore { static func deviceId() -> String /* 없으면 UUID 만들어 저장 */; static func token() -> String?; static func setToken(_:); static func clearToken() }`
  - `NWBrowser(for: .bonjour(type: DeckConstants.serviceType, domain: nil), using: .tcp)`로 첫 결과에 `NWConnection(to: result.endpoint, using: DeckNetwork.parameters())`. 끊기면 2초 뒤 다시 찾기. 브라우저 상태 `.waiting(.dns(-65555))`(NoAuth)면 `.localNetworkDenied`
  - `unauthorized` 받으면 토큰 지우고 다시 `hello` (허락 취소된 경우)
  - 볼륨 슬라이더 송신은 0.1초 간격으로 묶어 보낸다

- [ ] **Step 1:** 구현 (네트워크 의존이라 단위 테스트 대신 Task 6에서 끝까지 확인)
- [ ] **Step 2:** `xcodebuild build -scheme TouchDeck -destination 'generic/platform=iOS Simulator'` 성공
- [ ] **Step 3:** Commit `feat: iOS 클라이언트 연결과 페어링`

---

### Task 6: iOS 화면 (B안) 과 끝까지 확인

**Files:**
- Create: `TouchDeck/Views/*.swift` (File Structure 참고)

**Interfaces:**
- Consumes: Task 5 `DeckClient`
- 화면 규칙:
  - 가로(폭 > 높이): 왼쪽 4×3 격자 + 오른쪽 세로 볼륨 슬라이더(폭 약 72pt, 위에 스피커 아이콘 = 탭하면 음소거, 아래 숫자). 세로: 3열 격자 + 아래 가로 슬라이더. 어느 쪽이든 화면 스크롤 없음, 버튼 크기는 남은 공간을 나눠서
  - 페이지: `TabView` `.page` 스타일 + 페이지 점
  - 빈 칸: 점선 테두리 `+`, 탭 → `EditSheet`. 버튼: 탭 → `press`, 길게 누르기 → `EditSheet`(편집/삭제)
  - 버튼 모양: 앱은 받은 아이콘, 명령어는 `terminal` SF Symbol + 명령 글자(고정폭), 새 터미널은 `plus.rectangle.on.rectangle` 계열. 탭하면 살짝 눌림, `pressResult` 실패면 빨간 테두리 + 아래에 이유를 2초 표시
  - 연결 안 됨: 화면 위에 상태 띠 (찾는 중 / 연결 중 / 로컬 네트워크 권한 꺼짐이면 "설정 > 개인정보 보호 및 보안 > 로컬 네트워크에서 TouchDeck 켜기")
  - 페어링: `needsPairing`이면 4자리 입력 시트 ("맥 메뉴바의 TouchDeck 아이콘을 눌러 숫자를 확인하세요")
  - 편집 시트: 종류 세그먼트(앱 / 명령어 / 새 터미널). 앱 = 검색 가능한 아이콘 목록, 고르면 이름이 라벨 기본값. 명령어 = 라벨, 명령, 폴더(선택, 플레이스홀더 `~/Documents/Workspace/blog`). 새 터미널 = 라벨, 폴더(선택)
  - 디자인 세부는 `frontend-design` 원칙(밋밋한 기본 템플릿 피하기)을 SwiftUI에 맞게: 어두운 배경, 둥근 버튼, 종류별 강조색(목업 색: 앱 파랑, 명령 초록, 새 터미널 주황, 볼륨 보라)

- [ ] **Step 1:** 뷰 구현, `#Preview`에 가짜 배치 데이터
- [ ] **Step 2:** 빌드 성공
- [ ] **Step 3: 끝까지 확인 (이 맥에서)**
  1. 맥 앱 실행 → 메뉴바 아이콘 확인
  2. `xcrun simctl boot` iPad 시뮬레이터(가로) → 앱 설치/실행
  3. 페어링 숫자 입력 → 연결됨
  4. 빈 칸에 Safari 추가 → 탭 → Safari 열림
  5. 명령어 `blogrun`(폴더 `~/Documents/Workspace/blog`) 추가 → 탭 → Alacritty 새 창에서 jekyll 시작
  6. 명령어 `blogrn` → 실패 이유 표시
  7. 새 터미널 버튼 → Alacritty 창 하나 더
  8. 슬라이더 → 맥 볼륨 바뀜 (`osascript -e 'output volume of (get volume settings)'`로 확인)
  9. 13번째 버튼 → 2페이지로 넘어감
  10. 맥 메뉴에서 허락 취소 → 아이패드가 다시 페어링 요구
  11. 맥 앱 종료 → 상태 띠 "찾는 중", 다시 켜면 자동으로 붙음
  12. 아이폰 시뮬레이터 세로 화면 확인
  - 각 단계 화면은 `xcrun simctl io booted screenshot`으로 저장 (블로그용, `docs/screenshots/`)
- [ ] **Step 4:** Commit `feat: 아이패드 스트림덱 화면과 편집`

---

### Task 7: 블로그 시리즈

**Files:**
- Create: `~/Documents/Workspace/blog/_posts/StreamDeck/2026-10-19-StreamDeck (1).md` … (편수는 실제 진행에 맞춰)

- [ ] 스펙 3장 "블로그" 규칙 + 메모리의 블로그 규칙(헤더 형식, `##` 위 `---`, 백틱 없는 헤더, em dash 금지, 생략은 `// 생략`, 다음 글 예고 금지, last_modified_at 직접 기입, 다크/라이트 SVG)을 따른다
- [ ] 각 글: 낯선 개념 설명 → 실제 코드 → 실제로 만난 오류(메시지 원문, 원인, 해결) → 화면 캡처 → 참고자료
- [ ] 이미지 업로드/커밋/푸시는 하지 않는다. 이미지는 블로그 저장소의 기존 방식 확인 후 로컬에 두고 해롤드에게 알린다
- [ ] 흐름 시뮬레이터(버튼 누름 → 맥 → 실행 → 결과 순서, 페어링 핸드셰이크)는 기존 RunWay 시뮬레이터 형식을 확인하고 같은 방식으로
