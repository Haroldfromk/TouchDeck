import DeckKit
import SwiftUI

struct EditTarget: Identifiable {
    var id: String { "\(page)-\(index)" }
    let page: Int
    let index: Int
    let button: DeckButton?
}

/// 가로(아이패드 B안): 왼쪽 4×3 키 + 오른쪽 세로 볼륨. 세로(아이폰): 3×4 키 + 아래 가로 볼륨.
/// 화면 전체는 스크롤되지 않고, 페이지는 옆으로 밀어 넘긴다.
struct DeckView: View {
    @Bindable var client: DeckClient
    @State private var page = 0
    @State private var editing: EditTarget?
    @State private var failure: DeckClient.PressFeedback?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 14) {
                ConnectionStatusView(phase: client.phase)
                if landscape {
                    HStack(spacing: 18) {
                        pages(columns: DeckConstants.columns)
                        VolumeStrip(client: client, vertical: true)
                            .frame(width: 76)
                    }
                } else {
                    pages(columns: 3)
                    VolumeStrip(client: client, vertical: false)
                        .frame(height: 64)
                }
            }
            .padding(20)
            .disabled(!client.isConnected)
            .opacity(client.isConnected ? 1 : 0.55)
        }
        .background(DeckTheme.body.ignoresSafeArea())
        .overlay(alignment: .bottom) { failureBanner }
        .overlay(alignment: .bottom) { volumePermissionBanner }
        .sheet(item: $editing) { target in
            EditSheet(client: client, target: target)
        }
        .onChange(of: client.lastResult) { _, result in
            guard let result, !result.ok else { return }
            failure = result
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if failure == result { failure = nil }
            }
        }
        .onChange(of: client.layout.pages.count) { _, count in
            if page >= count { page = max(count - 1, 0) }
        }
        .preferredColorScheme(.dark)
    }

    private func pages(columns: Int) -> some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(client.layout.pages.enumerated()), id: \.offset) { pageIndex, deckPage in
                    grid(deckPage, page: pageIndex, columns: columns)
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: client.layout.pages.count, current: page)
        }
    }

    private func grid(_ deckPage: DeckPage, page pageIndex: Int, columns: Int) -> some View {
        let rows = DeckConstants.slotsPerPage / columns
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        let button = deckPage.buttons[index]
                        ButtonTile(
                            button: button,
                            icon: appIcon(button),
                            failed: failure?.page == pageIndex && failure?.index == index,
                            onTap: { client.press(page: pageIndex, index: index) },
                            onEdit: { editing = EditTarget(page: pageIndex, index: index, button: button) }
                        )
                    }
                }
            }
        }
    }

    private func appIcon(_ button: DeckButton?) -> UIImage? {
        guard case .app(let bundleId)? = button?.action else { return nil }
        return client.icons[bundleId]
    }

    /// 맥 앱에 손쉬운 사용 권한이 없으면 볼륨 키 신호를 못 보낸다. 켜는 곳을 알려준다.
    @ViewBuilder
    private var volumePermissionBanner: some View {
        if client.isConnected && !client.volumeKeysAllowed && failure == nil {
            Label("볼륨 키를 쓰려면 맥의 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 TouchDeck을 켜 주세요",
                  systemImage: "hand.raised.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(DeckTheme.legend)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DeckTheme.terminal.opacity(0.85), in: .capsule)
                .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let failure, let message = failure.message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(DeckTheme.legend)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DeckTheme.failure.opacity(0.9), in: .capsule)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? DeckTheme.legend : DeckTheme.legend.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("\(count)페이지 중 \(current + 1)페이지")
    }
}
