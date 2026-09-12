import AppKit
import Observation
import SwiftUI
import TodoTrainSync

@Observable
@MainActor
final class CompanionRideOverlayModel {
    var presentation = RideOverlayPresentation.hidden
    var isTucked = false
    var edge = OverlayEdge.trailing
}

struct CompanionRideOverlayView: View {
    @Bindable var model: CompanionRideOverlayModel
    var onPause: () -> Void
    var onResume: () -> Void
    var onPeekClick: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: RideOverlayPresentation { model.presentation }

    var body: some View {
        Group {
            if model.isTucked {
                peek
            } else {
                card
            }
        }
        .background(OverlayHoverTracking(isHovering: $hovering))
    }

    private var card: some View {
        HStack(spacing: 0) {
            handle
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .gesture(dragGesture)

                if let line = presentation.failureLine {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(RideOverlayPalette.overtime)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else if let status = presentation.statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 0)
                bottomRow
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(accessibilityRemaining)
    }

    private var handle: some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 4, height: 28)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityHidden(true)
    }

    private var bottomRow: some View {
        ZStack {
            progressRow
                .opacity(hovering ? 0 : 1)
                .allowsHitTesting(!hovering)
            actionRow
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .frame(height: 40)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovering)
    }

    private var progressRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black
                RideOverlayPalette.fill(for: presentation)
                    .frame(width: max(geo.size.width * presentation.progress, presentation.progress > 0 ? 4 : 0))
                Text(presentation.remainingLabel)
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityLabel("残り時間")
        .accessibilityValue(presentation.remainingLabel)
    }

    private var actionRow: some View {
        Button(action: primaryAction) {
            Text(presentation.canResume ? "再乗車" : "停車")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    presentation.canResume ? RideOverlayPalette.resume : RideOverlayPalette.progress
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(presentation.isSending || !(presentation.canPause || presentation.canResume))
        .accessibilityLabel(presentation.canResume ? "再乗車" : "停車")
    }

    private var peek: some View {
        VStack(spacing: 0) {
            RideOverlayPalette.fill(for: presentation)
                .overlay {
                    Text(presentation.peekTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .fixedSize()
                        .rotationEffect(.degrees(model.edge == .leading ? -90 : 90))
                }
                .contentShape(Rectangle())
            Image(systemName: model.edge == .leading ? "chevron.right" : "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture(perform: onPeekClick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue("隠しています")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("タップして戻す")
        .accessibilityAction(named: "戻す", onPeekClick)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onDragChanged(CGSize(width: value.translation.width, height: -value.translation.height))
            }
            .onEnded { value in
                onDragEnded(CGSize(width: value.translation.width, height: -value.translation.height))
            }
    }

    private var accessibilityRemaining: String {
        if presentation.isPaused { return "停車中 \(presentation.remainingLabel)" }
        if presentation.isOvertime { return "超過 \(presentation.remainingLabel)" }
        return "残り \(presentation.remainingLabel)"
    }

    private func primaryAction() {
        if presentation.canResume {
            onResume()
        } else if presentation.canPause {
            onPause()
        }
    }
}

private enum RideOverlayPalette {
    static let progress = Color(red: 0.93, green: 0.76, blue: 0.12)
    static let overtime = Color(red: 0.95, green: 0.35, blue: 0.32)
    static let resume = Color(red: 0.35, green: 0.82, blue: 0.52)

    static func fill(for presentation: RideOverlayPresentation) -> Color {
        if presentation.isOvertime { return overtime }
        if presentation.isPaused { return progress.opacity(0.7) }
        return progress
    }
}

/// Hover must use a tracking area with `.activeAlways` so a nonactivating panel still sees the pointer.
private struct OverlayHoverTracking: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> OverlayHoverView {
        let view = OverlayHoverView()
        view.onHover = { hovering in
            isHovering = hovering
        }
        return view
    }

    func updateNSView(_ nsView: OverlayHoverView, context: Context) {
        nsView.onHover = { hovering in
            isHovering = hovering
        }
    }
}

final class OverlayHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
