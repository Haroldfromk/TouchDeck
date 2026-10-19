import AppKit
import DeckKit
import Foundation

/// 버튼 동작을 실제로 실행한다. 바깥 세계(파일, 프로세스, NSWorkspace)와 닿는 부분은
/// 전부 클로저로 받아서 테스트에서 가짜로 바꿀 수 있게 했다.
struct ActionRunner: Sendable {
    struct AppNotFound: Error {}

    var commandExists: @Sendable (String) async -> Bool
    var directoryExists: @Sendable (String) -> Bool
    var isExecutable: @Sendable (String) -> Bool
    var alacrittyInstalled: @Sendable () -> Bool
    var openApp: @Sendable (String) async throws -> Void
    var runOpen: @Sendable ([String]) throws -> Void

    /// Alacritty 창 안에서 명령이 성공했는지는 맥 앱이 볼 수 없다.
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
            if let failure = checkTerminal(directory: directory) { return failure }
            switch check {
            case .lookup(let word):
                guard await commandExists(word) else { return (false, "\(word)을(를) 찾을 수 없음") }
            case .executable(let path):
                guard isExecutable(path) else { return (false, "실행 파일 없음: \(path)") }
            case .empty, .skip:
                break
            }
            return launch(AlacrittyCommand.openArguments(command: command, directory: directory, keepOpen: keepOpen))

        case .terminal(let directory):
            if let failure = checkTerminal(directory: directory) { return failure }
            return launch(AlacrittyCommand.openArguments(command: nil, directory: directory))
        }
    }

    private func checkTerminal(directory: String?) -> (ok: Bool, message: String?)? {
        guard alacrittyInstalled() else { return (false, "Alacritty가 설치되어 있지 않음") }
        if let directory {
            let path = AlacrittyCommand.expandTilde(directory)
            guard directoryExists(path) else { return (false, "폴더 없음: \(path)") }
        }
        return nil
    }

    private func launch(_ arguments: [String]) -> (ok: Bool, message: String?) {
        do {
            try runOpen(arguments)
            return (true, nil)
        } catch {
            return (false, "Alacritty 실행 실패: \(error.localizedDescription)")
        }
    }
}

extension ActionRunner {
    static let live = ActionRunner(
        commandExists: { word in
            await Task.detached {
                // 대화형 zsh(-i)라야 ~/.zshrc의 별칭이 보인다.
                // ~/.zshrc가 느리거나 멈추면 3초 뒤 확인을 건너뛰고 그냥 실행한다.
                do {
                    guard let status = try runProcess("/bin/zsh", ["-ic", AlacrittyCommand.lookupScript(for: word)],
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
        alacrittyInstalled: { FileManager.default.fileExists(atPath: AlacrittyCommand.appPath) },
        openApp: { bundleId in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { throw AppNotFound() }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        },
        runOpen: { arguments in
            let status = try runProcess("/usr/bin/open", arguments)
            if status != 0 { throw NSError(domain: "open", code: Int(status)) }
        }
    )

    /// 전부 성공하는 가짜. 테스트에서 필요한 것만 바꿔 쓴다.
    static func fake() -> ActionRunner {
        ActionRunner(
            commandExists: { _ in true },
            directoryExists: { _ in true },
            isExecutable: { _ in true },
            alacrittyInstalled: { true },
            openApp: { _ in },
            runOpen: { _ in }
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
