import AppKit
import DeckKit
import Foundation

/// 버튼 동작을 실제로 실행한다. 바깥 세계(파일, 프로세스, NSWorkspace)와 닿는 부분은
/// 전부 클로저로 받아서 테스트에서 가짜로 바꿀 수 있게 했다.
/// 고른 터미널을 지금 쓸 수 있는지
enum TerminalResolution: Equatable, Sendable {
    case ready(TerminalApp, appPath: String)
    /// 맥 메뉴에서 고른 터미널이 지워졌다. 다른 터미널로 몰래 바꾸지 않는다
    case missing(TerminalApp)
}

struct ActionRunner: Sendable {
    struct AppNotFound: Error {}

    var commandExists: @Sendable (String) async -> Bool
    var directoryExists: @Sendable (String) -> Bool
    var isExecutable: @Sendable (String) -> Bool
    var resolveTerminal: @Sendable () -> TerminalResolution
    var openApp: @Sendable (String) async throws -> Void
    var runOpen: @Sendable ([String]) throws -> Void
    /// AppleScript로 여는 터미널(기본 터미널, iTerm2): 소스 줄들과 보낼 글
    var runScript: @Sendable ([String], String) throws -> Void

    /// 터미널 창 안에서 명령이 성공했는지는 맥 앱이 볼 수 없다.
    /// 그래서 실행 전에 확인할 수 있는 것(폴더, 명령 이름이나 실행 파일 경로)만 확인한다.
    func run(_ action: ButtonAction) async -> (ok: Bool, message: String?) {
        switch action {
        case .app(let bundleId):
            do {
                try await openApp(bundleId)
                return (true, nil)
            } catch {
                return (false, "앱을 찾을 수 없음: \(bundleId)")
            }

        case .command(let command, let directory, let keepOpen):
            let check = AlacrittyCommand.preflight(command: command, directory: directory)
            if check == .empty { return (false, "명령이 비어 있음") }
            guard case .ready(let app, let appPath) = resolveTerminal() else { return missingTerminal() }
            if let failure = checkDirectory(directory) { return failure }
            switch check {
            case .lookup(let word):
                guard await commandExists(word) else { return (false, "\(word)을(를) 찾을 수 없음") }
            case .executable(let path):
                guard isExecutable(path) else { return (false, "실행 파일 없음: \(path)") }
            case .empty, .skip:
                break
            }
            return launch(app, app.launch(appPath: appPath, command: command, directory: directory, keepOpen: keepOpen))

        case .terminal(let directory):
            guard case .ready(let app, let appPath) = resolveTerminal() else { return missingTerminal() }
            if let failure = checkDirectory(directory) { return failure }
            return launch(app, app.launch(appPath: appPath, command: nil, directory: directory, keepOpen: true))
        }
    }

    private func missingTerminal() -> (ok: Bool, message: String?) {
        guard case .missing(let app) = resolveTerminal() else { return (false, nil) }
        return (false, "\(app.name)을(를) 찾을 수 없어요. 맥 메뉴에서 다른 터미널을 고르세요")
    }

    private func checkDirectory(_ directory: String?) -> (ok: Bool, message: String?)? {
        if let directory {
            let path = AlacrittyCommand.expandTilde(directory)
            guard directoryExists(path) else { return (false, "폴더 없음: \(path)") }
        }
        return nil
    }

    private func launch(_ app: TerminalApp, _ plan: TerminalLaunch) -> (ok: Bool, message: String?) {
        switch plan {
        case .open(let arguments):
            do {
                try runOpen(arguments)
                return (true, nil)
            } catch {
                return (false, "\(app.name) 실행 실패: \(error.localizedDescription)")
            }
        case .appleScript(let lines, let text):
            do {
                try runScript(lines, text)
                return (true, nil)
            } catch {
                // 거의 늘 자동화 허락이 꺼져 있는 경우다
                return (false, "\(app.name)을(를) 열지 못했어요. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 TouchDeck을 켜 주세요")
            }
        }
    }
}

extension ActionRunner {
    static let live = ActionRunner(
        commandExists: { word in
            await Task.detached {
                // 실행할 때와 같은 셸(-lic)로 찾아야 ~/.zshrc의 별칭과 ~/.zprofile의 Homebrew 경로가 보인다.
                // ~/.zshrc가 느리거나 멈추면 3초 뒤 확인을 건너뛰고 그냥 실행한다.
                do {
                    guard let status = try runProcess("/bin/zsh", [AlacrittyCommand.shellFlags, AlacrittyCommand.lookupScript(for: word)],
                                                      timeout: .seconds(3)) else { return true }
                    return status == 0
                } catch {
                    return false
                }
            }.value
        },
        directoryExists: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        },
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        resolveTerminal: { TerminalSettings.resolve() },
        openApp: { bundleId in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { throw AppNotFound() }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        },
        runOpen: { arguments in
            let status = try runProcess("/usr/bin/open", arguments)
            if status != 0 { throw NSError(domain: "open", code: Int(status)) }
        },
        runScript: { lines, text in
            // 명령 글자는 소스에 넣지 않고 마지막 인자(argv)로 넘긴다
            let status = try runProcess("/usr/bin/osascript", lines.flatMap { ["-e", $0] } + [text])
            if status != 0 { throw NSError(domain: "osascript", code: Int(status)) }
        }
    )

    /// 전부 성공하는 가짜. 테스트에서 필요한 것만 바꿔 쓴다.
    static func fake() -> ActionRunner {
        ActionRunner(
            commandExists: { _ in true },
            directoryExists: { _ in true },
            isExecutable: { _ in true },
            resolveTerminal: { .ready(.alacritty, appPath: AlacrittyCommand.appPath) },
            openApp: { _ in },
            runOpen: { _ in },
            runScript: { _, _ in }
        )
    }
}

/// 프로세스를 실행하고 끝날 때까지 기다려 종료 코드를 돌려준다.
@discardableResult
func runProcess(_ path: String, _ arguments: [String], output: Pipe? = nil) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(filePath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output ?? FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

/// 시간 제한이 있는 runProcess. 제한을 넘기면 프로세스를 죽이고 nil을 돌려준다.
/// 대화형 zsh는 SIGTERM을 무시해서 SIGKILL로 죽인다.
func runProcess(_ path: String, _ arguments: [String], timeout: Duration) throws -> Int32? {
    let process = Process()
    process.executableURL = URL(filePath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    if finished.wait(timeout: .now() + seconds) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        return nil
    }
    return process.terminationStatus
}
