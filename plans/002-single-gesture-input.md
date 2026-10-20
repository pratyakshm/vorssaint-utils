# 002 — One gesture input for title swipe

- **Status**: DONE
- **Commit**: 68df79e8
- **Severity**: HIGH
- **Category**: Cohesion & tokens
- **Estimated scope**: 2 files, ~60 lines removed

## Problem

One action has three input paths. They fight and duplicate threshold logic. Locations:

1. Trackpad scroll at `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:101`:
```swift
override func scrollWheel(with event: NSEvent) {
```

2. Discrete swipe at `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:149`:
```swift
override func swipe(with event: NSEvent) {
    guard isEnabled else { super.swipe(with: event); return }
    if event.deltaX < 0 { onCommit?(.next) }
    else if event.deltaX > 0 { onCommit?(.previous) }
    else { super.swipe(with: event) }
}
```

3. Mouse drag at `Sources/Vorssaint/UI/Notch/NotchView.swift:571-600`:
```swift
.gesture(
    DragGesture(minimumDistance: 20, coordinateSpace: .local)
```

Plus an empty touch claim at `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:157`:
```swift
override func touchesBegan(with event: NSEvent) {
}
```

The `swipe(with:)` path may never fire in a borderless `NSPanel`. The `DragGesture` path adds velocity logic (`predictedEndTranslation`, `abs(velocity) > 120`) that the scroll path lacks. Three thresholds drift apart. The empty `touchesBegan` swallows touches for no benefit.

## Target

Keep `scrollWheel` only. Delete `swipe(with:)`, `touchesBegan`, and the `DragGesture`. End state of the catcher:

```swift
final class NotchSectionSwipeNSView: NSView {
    var isEnabled = true
    var onChanged: ((CGFloat) -> Void)?
    var onCommit: ((NotchSectionSwipeDirection) -> Void)?
    var onCancelled: (() -> Void)?
    private var accumulated: CGFloat = 0
    private var tracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { super.scrollWheel(with: event); return }
        guard event.momentumPhase.isEmpty else { return }
        let precise = event.hasPreciseScrollingDeltas
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard dx.isFinite, dy.isFinite else { return }
        if !precise, event.phase.isEmpty {
            if dx < 0 { onCommit?(.next) } else if dx > 0 { onCommit?(.previous) }
            return
        }
        if abs(dy) > abs(dx) * 1.5, !tracking {
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.began) {
            accumulated = 0
            tracking = true
        } else if !tracking, event.phase.isEmpty {
            tracking = true
        }
        guard tracking else { return }
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
}
```

Title keeps only the catcher background. No `.gesture(DragGesture...)`.

## Repo conventions to follow

- Scroll handling lives in `NSView.scrollWheel` in this repo. Exemplar at `Sources/Vorssaint/UI/Notch/NotchTimerRuler.swift:98`:
```swift
override func scrollWheel(with event: NSEvent) {
```
- Vertical travel passes to super so the panel handler keeps open and close. Keep that branch.

## Steps

1. In `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift`, delete the full `swipe(with:)` override and the full `touchesBegan` override.
2. In `Sources/Vorssaint/UI/Notch/NotchView.swift:571-600`, delete the whole `.gesture(DragGesture...)` block including the `including:` line. Keep `.background`, `.contentShape`, `.accessibilityAddTraits`, `.accessibilityHint`.
3. Update the doc comment at `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:49-53` to name `scrollWheel` only.

## Boundaries

- Do NOT touch spring values or commit timing in this plan. That is plan 001.
- Do NOT change markup or structure. Input paths only.
- Do NOT add new dependencies.
- If a step doesn't match the code you find (drift since commit 68df79e8), STOP and report instead of improvising.

## Verification

- **Mechanical**: parse check with `swiftc -parse Sources/Vorssaint/UI/Notch/NotchView.swift Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift`. Expect exit 0. Grep for `DragGesture` in `NotchView.swift` returns nothing. Grep for `func swipe` in `NotchSectionSwipe.swift` returns nothing.
- **Feel check**: open the island. Two-finger horizontal scroll on the title switches sections. Vertical scroll on the title still opens and closes via the panel handler. No dead clicks on nearby buttons.
- **Done when**: one input path remains. Threshold logic lives in one place.
