import DeckKit
import SwiftUI

/// "맥 화면" 탭: 맥 모니터를 미리보기 카드로 보여주고, 고르면 전체 화면으로 본다.
/// 미리보기는 이 화면을 열 때만 맥에 달라고 한다.
struct ScreenPickerView: View {
    let client: DeckClient
    /// 보기 화면의 "닫기": 스트림덱 탭으로 돌아간다
    let onClose: () -> Void
    @State private var viewing: DisplayInfo?
    /// 목록을 달라고 한 뒤 5초가 지나도 답이 없다
    @State private var noReply = false
    @State private var requestCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("볼 모니터를 고르세요")
                    .font(DeckTheme.legendFont(size: 17))
                    .foregroundStyle(DeckTheme.legendDim)
                Spacer()
                Button {
                    requestDisplays()
                } label: {
                    Label("다시 불러오기", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                }
                .tint(DeckTheme.legend)
            }

            if let notice = client.screenNotice, let text = Self.text(for: notice) {
                Label(text, systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DeckTheme.legend)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DeckTheme.terminal.opacity(0.22), in: .rect(cornerRadius: 12))
            }

            if client.displays.isEmpty && client.screenNotice == nil {
                if noReply {
                    // 화면 기능 전의 맥 앱은 모르는 메시지를 답 없이 버린다
                    Label("맥이 답하지 않아요. 맥의 TouchDeck이 화면 기능 전 버전일 수 있어요. 맥 앱을 새로 빌드해서 설치해 주세요",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(DeckTheme.legend)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DeckTheme.terminal.opacity(0.22), in: .rect(cornerRadius: 12))
                } else {
                    ProgressView("맥 모니터 목록을 불러오는 중")
                        .tint(DeckTheme.legend)
                        .foregroundStyle(DeckTheme.legendDim)
                        .frame(maxWidth: .infinity)
                }
            }

            GeometryReader { geo in
                let columns = client.displays.count <= 1 ? 1 : (geo.size.width > geo.size.height ? min(client.displays.count, 3) : 2)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                        ForEach(client.displays, id: \.id) { display in
                            DisplayCard(display: display, thumbnail: client.displayThumbnails[display.id]) {
                                client.startScreen(display.id)
                                viewing = display
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear { requestDisplays() }
        .onChange(of: client.isConnected) { _, connected in
            if connected { requestDisplays() } else { viewing = nil }
        }
        .task(id: requestCount) {
            noReply = false
            try? await Task.sleep(for: .seconds(5))
            if client.isConnected && client.displays.isEmpty && client.screenNotice == nil { noReply = true }
        }
        .fullScreenCover(item: $viewing) { display in
            ScreenViewer(client: client, display: display,
                         onChangeMonitor: {
                             client.stopScreen()
                             viewing = nil
                             requestDisplays()
                         },
                         onClose: {
                             client.stopScreen()
                             viewing = nil
                             onClose()
                         })
        }
    }

    private func requestDisplays() {
        client.listDisplays()
        requestCount += 1
    }

    /// 맥이 보여줄 수 없다고 답한 이유와 고치는 곳
    static func text(for notice: DeckClient.ScreenNotice) -> String? {
        switch notice.state {
        case .ok: nil
        case .notAllowed: "맥 메뉴바의 TouchDeck에서 이 기기의 \"화면 보기 허용\"을 켜 주세요"
        case .noPermission: "맥의 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹화에서 TouchDeck을 켜고, TouchDeck을 다시 실행해 주세요"
        case .busy: "\(notice.message ?? "다른 기기")에서 맥 화면을 보고 있어요"
        case .locked: "맥이 잠겨 있어요. 잠금을 풀고 다시 골라 주세요"
        case .stopped: notice.message ?? "화면 보기가 끝났어요"
        case .noInput: "화면은 보이지만, 조작하려면 맥의 손쉬운 사용 권한이 필요해요"
        }
    }
}

private struct DisplayCard: View {
    let display: DisplayInfo
    let thumbnail: UIImage?
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(DeckTheme.socket)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 6))
                            .padding(8)
                    } else {
                        Image(systemName: "display")
                            .font(.system(size: 34))
                            .foregroundStyle(DeckTheme.legendDim)
                    }
                }
                .aspectRatio(CGFloat(max(display.width, 1)) / CGFloat(max(display.height, 1)), contentMode: .fit)

                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(DeckTheme.legendFont(size: 16))
                        .foregroundStyle(DeckTheme.legend)
                        .lineLimit(1)
                    Text("\(display.width) × \(display.height)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DeckTheme.legendDim)
                }
            }
            .padding(12)
            .background(DeckTheme.keycap, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(display.name), \(display.width) 곱하기 \(display.height)")
    }
}

extension DisplayInfo: @retroactive Identifiable {}
