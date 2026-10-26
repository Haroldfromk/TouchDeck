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
    /// 끄는 버튼의 위치를 재는 좌표. 페이지 하나가 보이는 칸과 같다
    static let gridSpace = "deckGrid"
    private static let spacing: CGFloat = 14

    /// 끌려 나간 버튼. 손가락을 따라 그리드 위에 떠 있다
    struct Lift {
        let page: Int
        let index: Int
        let button: DeckButton
        var location: CGPoint
    }

    @Bindable var client: DeckClient
    @State private var page = 0
    @State private var editing: EditTarget?
    @State private var showRemote = false
    @State private var failure: DeckClient.PressFeedback?
    /// 맥이 "실행했음"을 돌려준 버튼. 잠깐 테두리가 빛난다
    @State private var success: DeckClient.PressFeedback?
    /// 스트림덱 / 숫자 키패드 / 맥 화면. 마지막에 고른 화면을 기억한다
    @AppStorage("screen") private var screen = Screen.deck
    /// 버튼 옮기기 모드. 버튼들이 흔들리고, "완료"를 누르면 끝난다
    @State private var arranging = false
    @State private var lift: Lift?
    /// 끄는 버튼이 놓일 칸(지금 보이는 페이지)
    @State private var target: Int?
    @State private var pager = EdgePager()
    /// 손으로 페이지를 미는 중인 거리
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.3))) private var swipe: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    enum Screen: String, CaseIterable {
        case deck = "스트림덱"
        case keypad = "숫자 키패드"
        case screen = "맥 화면"
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        // 오른쪽 "밖에서 붙기" 버튼으로 밖에서 붙을 맥 주소를 넣는다
                        ConnectionStatusView(phase: client.phase, route: client.shownRoute, remoteFailed: client.remoteFailed,
                                             macLocked: client.canUnlock && client.macLocked,
                                             onRemote: { showRemote = true },
                                             onLock: client.showsLock ? { client.lockMac() } : nil)
                        if client.macNeedsUpdate {
                            Label("맥 TouchDeck을 새 버전으로 설치해 주세요", systemImage: "arrow.down.circle")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DeckTheme.legendDim)
                        }
                    }
                    if arranging {
                        Button("완료") { endArranging() }
                            .buttonStyle(.borderedProminent)
                            .font(.headline)
                    } else {
                        Picker("화면", selection: $screen) {
                            ForEach(Screen.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .disabled(!client.isUsable)
                    }
                }
                // 맥 화면 탭은 모니터 카드를 넓게 쓰려고 볼륨 칸을 숨긴다
                // 상태 줄의 "밖에서 붙기"는 끊겨 있을 때도 눌려야 해서 아래쪽만 막는다
                Group {
                    if screen == .screen {
                        main(columns: DeckConstants.columns)
                    } else if landscape {
                        HStack(spacing: 18) {
                            main(columns: DeckConstants.columns)
                            VolumeStrip(client: client, vertical: true)
                                .frame(width: 76)
                        }
                    } else {
                        main(columns: 3)
                        VolumeStrip(client: client, vertical: false)
                            .frame(height: 64)
                    }
                }
                .disabled(!client.isUsable)
            }
            .padding(20)
            .opacity(client.isUsable ? 1 : 0.55)
        }
        .background(DeckTheme.body.ignoresSafeArea())
        .overlay(alignment: .bottom) { failureBanner }
        .overlay(alignment: .bottom) { volumePermissionBanner }
        .sheet(isPresented: $showRemote) { RemoteSettingsSheet(client: client) }
        .sheet(item: $editing) { target in
            EditSheet(client: client, target: target)
        }
        .onChange(of: client.lastResult) { _, result in
            guard let result else { return }
            if result.ok {
                success = result
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    if success == result { success = nil }
                }
                return
            }
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
        // 맥이 잠기거나 끊기면, 앱이 뒤로 가면 옮기기 모드를 끝낸다
        .onChange(of: client.isUsable) { _, usable in
            if !usable { endArranging() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { endArranging() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func main(columns: Int) -> some View {
        switch screen {
        case .deck: pages(columns: columns)
        case .keypad: KeypadView(client: client)
        case .screen: ScreenPickerView(client: client, onClose: { screen = .deck })
        }
    }

    /// 페이지를 옆으로 늘어놓고 지금 페이지만 보이게 민다. TabView는 안 보이는 페이지를 치워서
    /// 끄는 중에 페이지를 넘기면 끌던 손짓이 끊기고, 버튼을 끄는 손짓과 페이지 밀기가 다퉈서 직접 그린다
    private func pages(columns: Int) -> some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let size = geo.size
                HStack(spacing: 0) {
                    ForEach(Array(client.layout.pages.enumerated()), id: \.offset) { pageIndex, deckPage in
                        grid(deckPage, page: pageIndex, columns: columns, size: size)
                            .frame(width: size.width, height: size.height)
                    }
                }
                .offset(x: -CGFloat(page) * size.width + swipe)
                .frame(width: size.width, height: size.height, alignment: .leading)
                .animation(.spring(duration: 0.3), value: page)
                .overlay { liftedTile(columns: columns, size: size) }
                .contentShape(.rect)
                .gesture(pageSwipe(width: size.width))
                // 손가락이 가장자리에 가만히 있어도 시간이 가야 페이지가 넘어간다
                .task(id: lift == nil) {
                    while !Task.isCancelled, let current = lift {
                        flipIfAtEdge(x: current.location.x, width: size.width)
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }
            .coordinateSpace(.named(Self.gridSpace))
            .clipped()

            PageDots(count: client.layout.pages.count, current: page)
        }
    }

    private func pageSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .updating($swipe) { value, state, _ in
                guard lift == nil else { return }
                let dx = value.translation.width
                // 첫 페이지 왼쪽, 마지막 페이지 오른쪽은 조금만 끌려 온다
                let atEnd = (page == 0 && dx > 0) || (page == client.layout.pages.count - 1 && dx < 0)
                state = atEnd ? dx / 3 : dx
            }
            .onEnded { value in
                guard lift == nil else { return }
                let dx = value.predictedEndTranslation.width
                if dx < -width / 3 { page = min(page + 1, client.layout.pages.count - 1) }
                if dx > width / 3 { page = max(page - 1, 0) }
            }
    }

    @ViewBuilder
    private func liftedTile(columns: Int, size: CGSize) -> some View {
        if let lift {
            let rows = DeckConstants.slotsPerPage / columns
            ButtonTile(button: lift.button, icon: appIcon(lift.button), failed: false, onTap: {}, onEdit: {})
                .frame(width: (size.width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns),
                       height: (size.height - Self.spacing * CGFloat(rows - 1)) / CGFloat(rows))
                .scaleEffect(1.1)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .position(lift.location)
                .allowsHitTesting(false)
        }
    }

    private func dragChanged(page pageIndex: Int, index: Int, button: DeckButton?, location: CGPoint,
                             first: Bool, columns: Int, size: CGSize) {
        if lift == nil {
            // 끄는 도중 옮기기 모드가 끝났으면(잠김 등) 손을 뗄 때까지 다시 집어 들지 않는다
            guard first, let button else { return }
            arranging = true
            lift = Lift(page: pageIndex, index: index, button: button, location: location)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        lift?.location = location
        target = GridSlot.index(at: location, size: size, columns: columns, spacing: Self.spacing)
        flipIfAtEdge(x: location.x, width: size.width)
    }

    private func flipIfAtEdge(x: CGFloat, width: CGFloat) {
        let flip = pager.update(x: x, width: width, page: page, pageCount: client.layout.pages.count,
                                now: Date().timeIntervalSinceReferenceDate)
        if flip != 0 { page += flip }
    }

    private func dragEnded(at location: CGPoint?, columns: Int, size: CGSize) {
        defer {
            lift = nil
            target = nil
            pager.reset()
        }
        // 칸 사이나 그리드 밖에서 떼면 원래 자리로
        guard let lift, let location,
              let index = GridSlot.index(at: location, size: size, columns: columns, spacing: Self.spacing) else { return }
        client.moveButton(fromPage: lift.page, fromIndex: lift.index, toPage: page, toIndex: index)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func endArranging() {
        arranging = false
        lift = nil
        target = nil
        pager.reset()
    }

    private func grid(_ deckPage: DeckPage, page pageIndex: Int, columns: Int, size: CGSize) -> some View {
        let rows = DeckConstants.slotsPerPage / columns
        return Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        let button = deckPage.buttons[index]
                        ButtonTile(
                            button: button,
                            icon: appIcon(button),
                            failed: failure?.page == pageIndex && failure?.index == index,
                            succeeded: success?.page == pageIndex && success?.index == index,
                            arranging: arranging,
                            phase: Double(index) * 0.13,
                            lifted: lift?.page == pageIndex && lift?.index == index,
                            highlighted: lift != nil && page == pageIndex && target == index
                                && !(lift?.page == pageIndex && lift?.index == index),
                            canDrag: client.canArrange,
                            onDragChanged: { location, first in
                                dragChanged(page: pageIndex, index: index, button: button, location: location,
                                            first: first, columns: columns, size: size)
                            },
                            onDragEnded: { location in dragEnded(at: location, columns: columns, size: size) },
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
