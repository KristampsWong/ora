//
//  RecordingOverlayController.swift
//  ora
//
//  AppKit NSPanel host for the dictation overlay. Ported from the
//  prior whisper project, with one M6 addition: an `isShowing`
//  accessor so DictationCoordinator can decide between
//  show(phase:) (panel creator, no-op if already up) and direct
//  state.phase mutation (live update on an existing panel).
//
//  ## API contract
//
//  Three operations with deliberately different semantics — see
//  `docs/2026-04-09-m6-dictation-coordinator-design.md` § Overlay API
//  contract for the full table.
//
//   - `show(phase:)`  : create the panel + set initial phase. **No-op
//                       if a panel already exists** (will not even
//                       update state.phase). First-show only.
//   - `state.phase`   : live mutation while the panel is on screen.
//                       Triggers SwiftUI to re-render.
//   - `hide()`        : close the panel, reset audioLevel, set
//                       state.phase = .done as housekeeping.
//
//  Coordinator code MUST go through the `present(_)` / `dismiss()`
//  helpers in DictationCoordinator rather than calling these directly.
//

import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    let state = RecordingOverlayState()

    /// True iff the NSPanel currently exists. Used by
    /// DictationCoordinator.present(_) to pick between show(phase:)
    /// and direct state.phase mutation. M6 addition (not in the
    /// original whisper port).
    var isShowing: Bool { panel != nil }

    func show(phase: OverlayPhase = .recording) {
        guard panel == nil else { return }

        state.phase = phase

        let content = RecordingOverlayView(state: state)
        let hosting = NSHostingView(rootView: content)
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.contentView = hosting
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.maxY - 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
        state.phase = .done
        state.audioLevel = 0
    }
}
