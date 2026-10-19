import XCTest

/// 맥에서 TouchDeck(디버그, TOUCHDECK_DEBUG_PAIR_CODE=4821)을 띄워 둔 채로 돌린다.
/// 실제로 맥에서 Safari와 Alacritty가 열린다.
@MainActor
final class EndToEndUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testEndToEnd() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        pairIfNeeded(shot: "01-pairing")
        waitForConnected()
        shot("02-connected-empty")

        addApp(named: "Safari", shot: "03-edit-app")
        addApp(named: "Xcode")
        addApp(named: "Finder")
        addCommand("blogrun", directory: "~/Documents/Workspace/blog", shot: "04-edit-command")
        addCommand("blogrn", label: "오타 명령")
        addTerminal()
        sleep(1)
        shot("05-deck-filled")

        key("Safari").tap()
        sleep(2)

        key("오타 명령").tap()
        XCTAssertTrue(app.staticTexts["blogrn을(를) 찾을 수 없음"].waitForExistence(timeout: 8))
        shot("06-failure")

        key("새 터미널").tap()
        sleep(2)
        key("blogrun").tap()
        sleep(3)

        key("Safari").press(forDuration: 0.8)
        XCTAssertTrue(app.navigationBars["버튼 편집"].waitForExistence(timeout: 5))
        shot("07-edit-existing")
        app.buttons["취소"].tap()
    }

    /// 키 교환으로 페어링하고, 서명된 메시지로 버튼 추가와 누르기가 되는지
    func testSignedSession() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        pairIfNeeded(shot: "14-pairing-keyexchange")
        waitForConnected()
        addApp(named: "Finder")
        key("Finder").tap()
        sleep(2)
        shot("15-signed-session")
    }

    /// 2페이지까지 버튼이 채워진 뒤(스크립트로 채움) 옆으로 넘겨 본다.
    func testSecondPage() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        waitForConnected()
        sleep(1)
        shot("08-page1-full")
        app.swipeLeft()
        sleep(1)
        shot("09-page2")
    }

    /// 아이폰 세로 화면 확인용
    func testPhonePortrait() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        pairIfNeeded(shot: nil)
        waitForConnected()
        sleep(2)
        shot("10-iphone")
    }

    // MARK: - 도우미

    private func pairIfNeeded(shot name: String?) {
        let field = app.textFields["페어링 숫자"]
        guard field.waitForExistence(timeout: 15) else { return }
        if let name { shot(name) }
        field.tap()
        field.typeText("4821")
    }

    private func waitForConnected() {
        let connected = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '연결됨'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 60), "맥에 연결되지 않음")
    }

    private func key(_ label: String) -> XCUIElement {
        let element = app.buttons[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(label) 버튼 없음")
        return element
    }

    private func openEmptySlot() {
        key("빈 칸").tap()
        XCTAssertTrue(app.navigationBars["버튼 추가"].waitForExistence(timeout: 5))
    }

    private func addApp(named name: String, shot name2: String? = nil) {
        openEmptySlot()
        // 목록은 화면에 보이는 줄만 만들어서, 검색어를 먼저 넣어야 뒤쪽 앱이 나타난다
        let anyApp = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Books' OR label CONTAINS 'App Store'")).firstMatch
        _ = anyApp.waitForExistence(timeout: 20)
        if let name2 { shot(name2) }
        let search = app.textFields["앱 검색"]
        search.tap()
        search.typeText(name)
        let row = app.buttons[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "앱 목록에 \(name) 없음")
        row.tap()
        app.buttons["저장"].tap()
    }

    private func addCommand(_ command: String, label: String? = nil, directory: String? = nil, shot name: String? = nil) {
        openEmptySlot()
        app.buttons["명령어"].tap()
        if let label {
            let field = app.textFields["이름 (비우면 명령 그대로)"]
            field.tap(); field.typeText(label)
        }
        let commandField = app.textFields["명령 (예: blogrun)"]
        commandField.tap(); commandField.typeText(command)
        if let directory {
            let dirField = app.textFields["실행할 폴더 (선택, 예: ~/Documents/Workspace/blog)"]
            dirField.tap(); dirField.typeText(directory)
        }
        if let name { shot(name) }
        app.buttons["저장"].tap()
    }

    private func addTerminal() {
        openEmptySlot()
        app.buttons["새 터미널"].tap()
        app.buttons["저장"].tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
