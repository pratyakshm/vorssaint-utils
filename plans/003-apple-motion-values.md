# 003 — Apple motion values for section swipe

- **Status**: DONE
- **Commit**: 68df79e8
- **Severity**: MEDIUM
- **Category**: Easing & duration
- **Estimated scope**: 2 files, ~15 lines changed

## Problem

Swipe motion uses hand-picked springs that do not match repo tokens or Apple values. Current code:

At `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:23-25`:
```swift
static func spring() -> Animation {
    .spring(response: 0.38, dampingFraction: 0.82)
}
```

At `Sources/Vorssaint/UI/Notch/NotchView.swift:353`:
```swift
withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
```

Two near-identical springs drift apart. Neither cites a token. Opacity and offset animate together, which is correct (transform plus opacity only), but the settle has no duration budget check.

## Target

One Apple-style spring from AUDIT.md section 4. Exact value: `{ type: "spring", duration: 0.5, bounce: 0.2 }`. In SwiftUI form:

```swift
.spring(duration: 0.5, bounce: 0.2)
```

Bounce stays in the 0.1–0.3 range. Total settle stays under 300ms of visible travel for the commit snap, with the spring tail allowed to 0.5 seconds per the Apple config. Movement animates `offset` (transform) and `opacity` only. No layout properties. Reduced motion drops movement and keeps the section change.

## Repo conventions to follow

- SwiftUI springs with duration and bounce in Notch UI. Exemplar at `Sources/Vorssaint/UI/Notch/NotchQuickAccessView.swift:22`:
```swift
let animation: Animation? = animated && visible ? .spring(duration: spring.duration, bounce: spring.bounce) : nil
```
- Small UI fades use `easeOut` under 200ms. Exemplar at `Sources/Vorssaint/UI/Notch/NotchScrollEdgeFade.swift:46`:
```swift
.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: beyondStart)
```
- Reduced motion pattern is `reduceMotion ? nil : <animation>`. Keep it on every motion line.

## Steps

1. In `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:17-25`, replace `spring()` with the Apple config or delete it and inline `.spring(duration: 0.5, bounce: 0.2)` at call sites.
2. In `Sources/Vorssaint/UI/Notch/NotchView.swift`, replace both `.spring(response:dampingFraction:)` calls with `.spring(duration: 0.5, bounce: 0.2)`.
3. Confirm `expanded` at `Sources/Vorssaint/UI/Notch/NotchView.swift:392-394` animates only `offset` and `opacity`. No width, height, or padding animation.
4. Confirm every `withAnimation` in the swipe path branches on `reduceMotion` and sets offset to 0 with no animation when true.

## Boundaries

- Do NOT touch gesture routing or interrupt logic in this plan. Those are plans 001 and 002.
- Do NOT change markup or structure. Motion values only.
- Do NOT add new dependencies.
- If a step doesn't match the code you find (drift since commit 68df79e8), STOP and report instead of improvising.

## Verification

- **Mechanical**: grep for `response:` in `NotchView.swift` section swipe code returns nothing. Grep for `spring(duration: 0.5, bounce: 0.2)` finds the commit and cancel paths.
- **Feel check**: swipe the title. Confirm the snap feels quick with a soft tail, no visible bounce. Toggle Reduce Motion. Confirm the section still changes with haptic feedback but no slide.
- **Done when**: one spring value drives cancel and commit. All swipe motion respects Reduce Motion.
