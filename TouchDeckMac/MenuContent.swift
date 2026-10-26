import DeckKit
import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 작은 창. 편집 화면은 두지 않는다 (편집은 아이패드/아이폰에서).
struct MenuContent: View {
    let server: DeckServer
    let keepAwake: KeepAwakeController
    var loginItem = LoginItem.live
    @State private var launchAtLogin = false
    @State private var loginError: String?
    @AppStorage(KeepAwake.key) private var keepAwakeOn = false
    /// 명령 버튼과 새 터미널 버튼을 열 터미널. 설치된 것만 보여 준다
    @State private var terminals: [TerminalApp] = []
    @State private var terminal: TerminalApp = .terminal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(server.status, systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)

            if let code = server.pairingCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(server.pairingDeviceName ?? "새 기기")에 이 숫자를 입력하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(6)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 8))
            }

            if server.isPairingLocked {
                VStack(alignment: .leading, spacing: 6) {
                    Text("페어링 숫자가 \(PairingAuthority.maxAttempts)번 틀려서 새 기기 허락을 멈췄어요.")
                        .font(.caption)
                    Button("새 기기 허락 다시 받기") { server.unlockPairing() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.12), in: .rect(cornerRadius: 8))
            }

            if let viewer = server.screen.viewerName {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("지금 화면을 보는 중: \(viewer)", systemImage: "eye.fill")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("끊기") { server.screen.disconnect() }
                    }
                    if let note = server.screen.speakerNote {
                        Label(note, systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.blue.opacity(0.15), in: .rect(cornerRadius: 8))
            }

            if server.trusted.contains(where: \.screenAllowed) && !server.screen.permission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("화면 보기에는 화면 기록 권한이 필요해요. 켠 뒤 TouchDeck을 다시 실행해 주세요.")
                        .font(.caption)
                    Button("화면 기록 설정 열기") {
                        ScreenPermission.request()
                        ScreenPermission.openSettings()
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 8))
            }

            section("연결된 기기") {
                if server.connectedDevices.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                } else {
                    ForEach(server.connectedDevices, id: \.self) { Text($0) }
                }
            }

            section("허락한 기기") {
                if server.trusted.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                } else {
                    ForEach(server.trusted, id: \.id) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Button("허락 취소") { server.revoke(deviceId: device.id) }
                                    .controlSize(.small)
                            }
                            Toggle("화면 보기 허용", isOn: Binding(
                                get: { device.screenAllowed },
                                set: { server.setScreenAllowed($0, deviceId: device.id) }
                            ))
                            .controlSize(.small)
                            Toggle("잠금 풀기 허용", isOn: Binding(
                                get: { device.unlockAllowed },
                                set: { server.setUnlockAllowed($0, deviceId: device.id) }
                            ))
                            .controlSize(.small)
                            if device.unlockAllowed {
                                Text("켜 두면 이 기기의 Face ID로 맥 잠금을 풀 수 있어요. 같은 와이파이나 가까이 있을 때만 돼요.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let last = server.lastUnlock {
                    Text("마지막 잠금 풀기: \(last.device), \(last.at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                // 사용자가 고를 때만 저장한다. 메뉴를 열며 화면을 채우는 것만으로는 바꾸지 않는다
                Picker("터미널", selection: Binding(
                    get: { terminal },
                    set: { app in
                        terminal = app
                        TerminalSettings.saved = app.bundleId
                    }
                )) {
                    ForEach(terminals, id: \.self) { Text($0.name).tag($0) }
                }
                if case .missing(let app) = TerminalSettings.resolve() {
                    Text("\(app.name)이(가) 지워졌어요. 다른 터미널을 고르세요")
                        .font(.caption).foregroundStyle(.secondary)
                } else if terminal.usesAppleScript {
                    Text("처음 한 번 macOS가 터미널 제어 허락을 물어봐요")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        loginError = loginItem.set(on)
                        launchAtLogin = loginItem.isOn
                    }
                ))
                if let note = loginError ?? (launchAtLogin ? loginItem.note : nil) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("잠자기 막기", isOn: $keepAwakeOn)
                    .onChange(of: keepAwakeOn) { keepAwake.refresh() }
                Text(keepAwakeOn ? "잠자기 막는 중. 맥이 잠들지도 잠기지도 않아요"
                     : "켜 두면 맥이 잠들지도 잠기지도 않아요. 밖에서 화면을 볼 때 켜 두세요")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("TouchDeck 종료") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
        // 시스템 설정에서 바꿨을 수도 있으니 창을 열 때마다 다시 읽는다
        .onAppear {
            launchAtLogin = loginItem.isOn
            // 터미널은 메뉴를 열 때마다 다시 찾는다(그사이 설치하거나 지웠을 수 있다)
            terminals = TerminalApp.allCases.filter { TerminalSettings.installed()[$0] != nil }
            switch TerminalSettings.resolve() {
            // 지워진 터미널이면 고르기 칸이 비어 보이고, 해롤드가 직접 다른 것을 고른다
            case .ready(let app, _), .missing(let app): terminal = app
            }
            server.screen.refreshPermission()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
