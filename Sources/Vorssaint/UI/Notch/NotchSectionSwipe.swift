// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A horizontal section change from the island's header title:
/// swiping left goes to the next section, right to the previous one,
/// in the same order the sections list shows.
enum NotchSectionSwipeDirection {
    case next
    case previous
}

/// Pure, testable rules for the header swipe. The view stays thin and the
/// AppKit catcher only reports points. This decides what they mean.
enum NotchSectionSwipeLogic {
    /// Points of finger travel that commit to another section.
    static let commitThreshold: CGFloat = 60
    /// Interactive travel never runs away. Beyond this it rubber-bands.
    static let maxOffset: CGFloat = 120

    static func direction(for offset: CGFloat, threshold: CGFloat = commitThreshold) -> NotchSectionSwipeDirection? {
        if offset <= -threshold { return .next }
        if offset >= threshold { return .previous }
        return nil
    }

    /// Damped follow: 1:1 inside the threshold, resisting past it.
    static func clamped(_ raw: CGFloat, max: CGFloat = maxOffset) -> CGFloat {
        guard raw.isFinite else { return 0 }
        let limit = max
        if abs(raw) <= limit { return raw }
        let sign: CGFloat = raw < 0 ? -1 : 1
        return sign * (limit + (abs(raw) - limit) * 0.35)
    }

    static func target(from selected: NotchModule?, modules: [NotchModule],
                       direction: NotchSectionSwipeDirection) -> NotchModule? {
        NotchSupport.adjacentModule(to: selected, modules: modules,
                                    backwards: direction == .previous)
    }
}

/// Catches 2-finger scroll over the header title.
/// `scrollWheel` carries the 2-finger trackpad scroll and a mouse tilt.
/// It reports through callbacks so the content follows the fingers.
/// Over a whole page it takes only scrolls: clicks, drags and menus fall
/// through to the controls beneath it.
struct NotchSectionSwipeCatcher: NSViewRepresentable {
    var enabled: Bool
    var takesOnlyScrolls = false
    var onChanged: (CGFloat) -> Void
    var onCommit: (NotchSectionSwipeDirection) -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> NotchSectionSwipeNSView {
        let view = NotchSectionSwipeNSView()
        view.onChanged = onChanged
        view.onCommit = onCommit
        view.onCancelled = onCancelled
        view.isEnabled = enabled
        view.takesOnlyScrolls = takesOnlyScrolls
        return view
    }

    func updateNSView(_ view: NotchSectionSwipeNSView, context: Context) {
        view.onChanged = onChanged
        view.onCommit = onCommit
        view.onCancelled = onCancelled
        view.isEnabled = enabled
        view.takesOnlyScrolls = takesOnlyScrolls
    }
}

final class NotchSectionSwipeNSView: NSView {
    var isEnabled = true
    var takesOnlyScrolls = false
    var onChanged: ((CGFloat) -> Void)?
    var onCommit: ((NotchSectionSwipeDirection) -> Void)?
    var onCancelled: (() -> Void)?

    private var accumulated: CGFloat = 0
    private var tracking = false
    /// Set while the view looks for what sits beneath itself, so its own
    /// hit test steps aside and the search reaches the page's controls.
    private var seekingUnderneath = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Transparent but present for hit testing over the title.
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, bounds.contains(point) else { return nil }
        if seekingUnderneath { return nil }
        // Over a page only a scroll lands here; every other event finds
        // the player's own controls beneath.
        if takesOnlyScrolls, NSApp.currentEvent?.type != .scrollWheel { return nil }
        return self
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { super.scrollWheel(with: event); return }
        // Momentum after the lift never navigates a second time.
        guard event.momentumPhase.isEmpty else { return }
        let precise = event.hasPreciseScrollingDeltas
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard dx.isFinite, dy.isFinite else { return }

        if !precise, event.phase.isEmpty {
            // A mouse tilt or an older wheel: one notch is one section.
            if dx < 0 { onCommit?(.next) } else if dx > 0 { onCommit?(.previous) }
            return
        }

        // Vertical travel belongs to the island's open/close gesture;
        // let it reach the panel's own handler, or the scroll view a page
        // keeps under the pointer.
        if abs(dy) > abs(dx) * 1.5, !tracking {
            forwardVertically(event)
            return
        }

        if event.phase.contains(.began) {
            accumulated = 0
            tracking = true
        } else if !tracking, event.phase.isEmpty {
            // Phaseless high-resolution glide without a beginning: start it.
            tracking = true
        }
        guard tracking else { return }

        // Natural direction: the content follows the fingers.
        let step = dx * CGFloat(event.isDirectionInvertedFromDevice ? 1 : -1)
        if step.isFinite { accumulated += step }
        onChanged?(NotchSectionSwipeLogic.clamped(accumulated))

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            tracking = false
            if let direction = NotchSectionSwipeLogic.direction(for: NotchSectionSwipeLogic.clamped(accumulated)) {
                accumulated = 0
                onCommit?(direction)
            } else {
                accumulated = 0
                onCancelled?()
            }
        }
    }

    /// Hands a non-section scroll to what sits under the pointer: a page's
    /// own scroll view takes it, and anything else rides the responder chain
    /// to the island's gesture handler, as if this view were not there.
    private func forwardVertically(_ event: NSEvent) {
        guard takesOnlyScrolls, let window, let contentView = window.contentView else {
            super.scrollWheel(with: event)
            return
        }
        seekingUnderneath = true
        let point = contentView.convert(event.locationInWindow, from: nil)
        var target = contentView.hitTest(point)
        seekingUnderneath = false
        while let view = target, !(view is NSScrollView) { target = view.superview }
        if let target { target.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}
