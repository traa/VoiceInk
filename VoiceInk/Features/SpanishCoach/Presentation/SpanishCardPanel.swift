import AppKit
import SwiftUI

@MainActor
final class SpanishCardPanel {
    static let shared = SpanishCardPanel()

    private static let visibleDuration: Duration = .seconds(8)
    private static let afterHoverDuration: Duration = .seconds(3)
    private static let bottomOffset: CGFloat = 74

    private var panel: NSPanel?
    private var hosting: NSHostingController<SpanishCardView>?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ card: SpanishCard) {
        closePanel(animated: false)

        let view = SpanishCardView(
            card: card,
            onPause: {
                SpanishCoachService.shared.pause(for: 3600)
                SpanishCardPanel.shared.dismiss()
            },
            onClose: { SpanishCardPanel.shared.dismiss() },
            onHoverChange: { SpanishCardPanel.shared.hoverChanged($0) }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting.view
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - size.width / 2, y: frame.minY + Self.bottomOffset))
        panel.alphaValue = 0
        // Never key: the user keeps typing in the app they dictated into.
        panel.orderFrontRegardless()

        self.panel = panel
        self.hosting = hosting

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        scheduleDismiss(after: Self.visibleDuration)
    }

    func dismiss() {
        closePanel(animated: true)
    }

    private func hoverChanged(_ isHovering: Bool) {
        if isHovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss(after: Self.afterHoverDuration)
        }
        // Let SwiftUI lay out the expanded/collapsed content, then fit the panel to it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.fitPanelToContent()
        }
    }

    /// Resizes keeping the bottom edge and horizontal centre fixed.
    private func fitPanelToContent() {
        guard let panel, let hosting else { return }
        let size = hosting.view.fittingSize
        let old = panel.frame
        let newFrame = NSRect(
            x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true)
    }

    private func scheduleDismiss(after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func closePanel(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }
        self.panel = nil
        self.hosting = nil
        guard animated else {
            panel.close()
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: { panel.close() })
    }
}

struct SpanishCardView: View {
    let card: SpanishCard
    let onPause: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sentenceText
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)

            if isHovering {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(card.chunks.enumerated()), id: \.offset) { _, chunk in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(chunk.spanish) — \(chunk.source)")
                                .font(.system(size: 13, weight: .semibold))
                            Text(chunk.gloss)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Pause for 1 hour", action: onPause)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Text("Spanish from what you just said")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .padding(14)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
    }

    /// The dictated sentence with each chunk's source range replaced by its Spanish.
    private var sentenceText: Text {
        var result = Text("")
        var cursor = card.sentence.startIndex
        for chunk in card.chunks {
            guard let range = card.sentence.range(
                of: chunk.source, options: .caseInsensitive, range: cursor..<card.sentence.endIndex)
            else { continue }
            result = result + Text(card.sentence[cursor..<range.lowerBound])
            result = result + Text(chunk.spanish).bold().foregroundColor(.accentColor)
            cursor = range.upperBound
        }
        return result + Text(card.sentence[cursor...])
    }
}

#Preview {
    SpanishCardView(
        card: SpanishCard(
            sentence: "I'm actually learning Spanish, so I'm very interested in that, and it could help me learn it.",
            chunks: [
                .init(source: "learning Spanish", spanish: "aprendiendo español", gloss: "aprendiendo = learning · español = Spanish"),
                .init(source: "it could help me", spanish: "podría ayudarme", gloss: "podría = could · ayudarme = help me"),
            ]),
        onPause: {}, onClose: {}, onHoverChange: { _ in })
}
