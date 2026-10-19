import DeckKit
import SwiftUI
import UIKit

/// 맥 화면 전체 보기. 탭=클릭, 두 손가락 탭=우클릭, 한 손가락 끌기=드래그, 두 손가락 쓸기=스크롤, 핀치=이 화면만 확대.
struct ScreenViewer: View {
    let client: DeckClient
    let display: DisplayInfo
    let onChangeMonitor: () -> Void
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @Environment(\.scenePhase) private var scenePhase

    private var stream: DeckClient.ScreenStream? {
        client.screenStream.flatMap { $0.displayId == display.id ? $0 : nil }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let stream {
                VideoSurface(client: client, video: CGSize(width: stream.width, height: stream.height),
                             macWidth: CGFloat(display.width), zoom: $zoom, offset: $offset)
                    .ignoresSafeArea()
            } else if let notice = client.screenNotice, let text = ScreenPickerView.text(for: notice) {
                Label(text, systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DeckTheme.legend)
                    .padding(24)
            } else {
                ProgressView("\(display.name) 화면을 불러오는 중")
                    .tint(DeckTheme.legend)
                    .foregroundStyle(DeckTheme.legendDim)
            }
        }
        .overlay(alignment: .topTrailing) { toolbar }
        .overlay(alignment: .bottom) { inputBanner }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // 앱이 뒤로 가면 맥에서 찍기를 멈추고, 돌아오면 같은 모니터로 다시 시작한다
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: client.stopScreen()
            case .active: if client.screenStream == nil { client.startScreen(display.id) }
            default: break
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolButton("모니터 바꾸기", systemImage: "rectangle.on.rectangle", action: onChangeMonitor)
            if zoom > 1.01 {
                toolButton("확대 원래대로", systemImage: "arrow.down.right.and.arrow.up.left") {
                    withAnimation(.snappy) {
                        zoom = 1
                        offset = .zero
                    }
                }
            }
            toolButton("닫기", systemImage: "xmark", action: onClose)
        }
        .padding(6)
        .background(.black.opacity(0.55), in: .capsule)
        .padding(14)
    }

    private func toolButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DeckTheme.legend)
    }

    @ViewBuilder
    private var inputBanner: some View {
        if stream != nil, let notice = client.screenNotice, notice.state == .noInput, let text = ScreenPickerView.text(for: notice) {
            Label(text, systemImage: "hand.raised.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(DeckTheme.legend)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DeckTheme.terminal.opacity(0.85), in: .capsule)
                .padding(.bottom, 24)
        }
    }
}

/// 영상 레이어와 제스처. 확대/이동은 영상에만 걸고, 터치 위치는 확대 전 화면 기준으로 되돌려 맥에 보낸다.
private struct VideoSurface: UIViewRepresentable {
    let client: DeckClient
    let video: CGSize
    /// 맥 모니터 너비(포인트). 스크롤 양을 맥 기준으로 바꿀 때 쓴다
    let macWidth: CGFloat
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView(videoLayer: client.video.layer)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        context.coordinator.parent = self
        view.videoView.transform = CGAffineTransform(translationX: offset.width, y: offset.height).scaledBy(x: zoom, y: zoom)
    }

    final class SurfaceView: UIView {
        let videoView = UIView()
        private let videoLayer: CALayer

        init(videoLayer: CALayer) {
            self.videoLayer = videoLayer
            super.init(frame: .zero)
            backgroundColor = .black
            clipsToBounds = true
            videoView.isUserInteractionEnabled = false
            videoView.layer.addSublayer(videoLayer)
            addSubview(videoView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 확대가 걸려 있어도 bounds/center로만 맞춘다 (frame은 transform과 섞이면 틀어진다)
            videoView.bounds = CGRect(origin: .zero, size: bounds.size)
            videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = videoView.bounds
            CATransaction.commit()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: VideoSurface
        private weak var view: UIView?

        /// 두 손가락 제스처를 시작할 때 정한다: 벌리면 확대(맥에 안 보냄), 그냥 쓸면 스크롤
        private enum TwoFinger { case undecided, zoom, scroll }
        private var twoFinger = TwoFinger.undecided
        private var pinchStartZoom: CGFloat = 1
        private var pinchScale: CGFloat = 1
        private var lastPanTranslation = CGPoint.zero
        private var pendingScroll = CGPoint.zero
        private var lastSent = Date.distantPast
        /// 끄는 중 마지막으로 영상 안에 있던 위치. 영상 밖에서 손을 떼도 여기서 뗀다
        private var lastDragPoint: CGPoint?

        init(_ parent: VideoSurface) {
            self.parent = parent
        }

        func attach(to view: UIView) {
            self.view = view
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            let twoTap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap(_:)))
            twoTap.numberOfTouchesRequired = 2
            let drag = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
            drag.minimumNumberOfTouches = 1
            drag.maximumNumberOfTouches = 1
            let twoPan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPan(_:)))
            twoPan.minimumNumberOfTouches = 2
            twoPan.maximumNumberOfTouches = 2
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            for g in [tap, twoTap, drag, twoPan, pinch] as [UIGestureRecognizer] {
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        // 핀치와 두 손가락 쓸기는 같이 들어와야 어느 쪽인지 고를 수 있다
        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated {
                (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            }
        }

        private func normalized(_ point: CGPoint) -> CGPoint? {
            guard let view else { return nil }
            return ScreenGeometry.normalized(touch: point, view: view.bounds.size, video: parent.video,
                                             zoom: parent.zoom, offset: parent.offset)
        }

        private func send(_ kind: PointerEvent.Kind, _ p: CGPoint, dx: Double = 0, dy: Double = 0) {
            parent.client.pointer(PointerEvent(kind: kind, x: p.x, y: p.y, dx: dx, dy: dy))
        }

        /// 움직임은 초당 60번까지만
        private func throttled() -> Bool {
            guard Date.now.timeIntervalSince(lastSent) >= 1.0 / 60 else { return false }
            lastSent = .now
            return true
        }

        @objc private func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let p = normalized(g.location(in: view)) else { return }
            send(.click, p)
        }

        @objc private func twoFingerTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let p = normalized(g.location(in: view)) else { return }
            send(.rightClick, p)
        }

        @objc private func drag(_ g: UIPanGestureRecognizer) {
            let here = g.location(in: view)
            switch g.state {
            case .began:
                // 두 손가락이면 스크롤이나 확대 쪽이다
                guard g.numberOfTouches == 1 else { return }
                // 끌기로 알아챈 순간엔 손가락이 조금 움직인 뒤라, 처음 닿은 곳에서 누른다
                let t = g.translation(in: view)
                guard let start = normalized(CGPoint(x: here.x - t.x, y: here.y - t.y)) else { return }
                lastDragPoint = start
                send(.down, start)
                if let p = normalized(here) {
                    lastDragPoint = p
                    send(.move, p)
                }
            case .changed:
                guard lastDragPoint != nil, let p = normalized(here) else { return }
                lastDragPoint = p
                if throttled() { send(.move, p) }
            case .ended, .cancelled, .failed:
                guard let last = lastDragPoint else { return }
                let p = normalized(here) ?? last
                send(.move, p)
                send(.up, p)
                lastDragPoint = nil
            default:
                break
            }
        }

        @objc private func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                pinchStartZoom = parent.zoom
                pinchScale = 1
            case .changed:
                pinchScale = g.scale
                if twoFinger == .undecided, abs(g.scale - 1) > 0.08 { twoFinger = .zoom }
                guard twoFinger == .zoom, let view else { return }
                let zoom = min(max(pinchStartZoom * g.scale, 1), 4)
                parent.zoom = zoom
                parent.offset = ScreenGeometry.clampOffset(parent.offset, zoom: zoom, view: view.bounds.size)
            default:
                break
            }
        }

        @objc private func twoFingerPan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: view)
            switch g.state {
            case .began:
                twoFinger = .undecided
                lastPanTranslation = t
                pendingScroll = .zero
            case .changed:
                let delta = CGPoint(x: t.x - lastPanTranslation.x, y: t.y - lastPanTranslation.y)
                lastPanTranslation = t
                if twoFinger == .undecided, hypot(t.x, t.y) > 12, abs(pinchScale - 1) <= 0.08 { twoFinger = .scroll }
                switch twoFinger {
                case .zoom:
                    // 확대하면서 손가락을 옮기면 확대한 영상이 따라 움직인다
                    guard let view else { return }
                    parent.offset = ScreenGeometry.clampOffset(
                        CGSize(width: parent.offset.width + delta.x, height: parent.offset.height + delta.y),
                        zoom: parent.zoom, view: view.bounds.size)
                case .scroll:
                    pendingScroll.x += delta.x
                    pendingScroll.y += delta.y
                    if throttled() { flushScroll(at: g.location(in: view)) }
                case .undecided:
                    break
                }
            case .ended, .cancelled, .failed:
                if twoFinger == .scroll { flushScroll(at: g.location(in: view)) }
                twoFinger = .undecided
                pinchScale = 1
            default:
                break
            }
        }

        /// 손가락이 움직인 만큼(아이패드 포인트)을 맥 포인트로 바꿔 보낸다. 내용이 손가락을 따라오는 방향
        private func flushScroll(at point: CGPoint) {
            guard pendingScroll != .zero, let view, let p = normalized(point) else { return }
            let shown = ScreenGeometry.videoRect(video: parent.video, in: view.bounds.size).width * parent.zoom
            let ratio = shown > 0 ? parent.macWidth / shown : 1
            send(.scroll, p, dx: pendingScroll.x * ratio, dy: pendingScroll.y * ratio)
            pendingScroll = .zero
        }
    }
}
