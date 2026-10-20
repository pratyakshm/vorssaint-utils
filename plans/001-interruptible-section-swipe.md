# 001 — Make section swipe interruptible with one spring

- **Status**: DONE
- **Commit**: 68df79e8
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 2 files, ~60 lines removed, ~20 lines added

## Problem

Title swipe uses two chained timers and a lock flag. A fast second swipe cannot interrupt the first. Code at `Sources/Vorssaint/UI/Notch/NotchView.swift:331`:

```swift
private func swipeCommitted(_ direction: NotchSectionSwipeDirection) {
    guard canSwipeSections, let target = swipeTarget(direction) else {
        swipeCancelled()
        return
    }
    guard target != service.selected else {
        swipeCancelled()
        return
    }
    sectionSwipeActive = false
    service.provideHapticFeedback()
    if reduceMotion {
        sectionSwipeOffset = 0
        service.select(target)
        return
    }
    let width = max(1, service.contentSize.width)
    let outgoing: CGFloat = direction == .next ? -width : width
    sectionSwipeSettling = true
    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
        sectionSwipeOffset = outgoing
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
        service.select(target)
        sectionSwipeOffset = -outgoing
        withAnimation(NotchSectionSwipeLogic.spring()) {
            sectionSwipeOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            sectionSwipeSettling = false
        }
    }
}
```

Guards at `Sources/Vorssaint/UI/Notch/NotchView.swift:315` and `:574` and `:581` drop all input while `sectionSwipeSettling` is true:

```swift
guard canSwipeSections, !sectionSwipeSettling else { return }
```

State at `Sources/Vorssaint/UI/Notch/NotchView.swift:17-19`:

```swift
@State private var sectionSwipeOffset: CGFloat = 0
@State private var sectionSwipeActive = false
@State private var sectionSwipeSettling = false
```

This breaks Apple's guideline for gesture motion. A drag must retarget from its current state. Fixed timers restart from zero. Rapid swipes desync. Reverse swipes lock out for 0.4 seconds.

## Target

One spring drives the whole swipe. No timers. No lock flag. New input retargets from the current offset at all times.

```swift
private func swipeChanged(_ offset: CGFloat) {
    guard canSwipeSections else { return }
    sectionSwipeOffset = offset
}

private func swipeCancelled() {
    guard sectionSwipeOffset != 0 else { return }
    if reduceMotion {
        sectionSwipeOffset = 0
    } else {
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { sectionSwipeOffset = 0 }
    }
}

private func swipeCommitted(_ direction: NotchSectionSwipeDirection) {
    guard canSwipeSections, let target = swipeTarget(direction) else {
        swipeCancelled()
        return
    }
    guard target != service.selected else {
        swipeCancelled()
        return
    }
    service.provideHapticFeedback()
    if reduceMotion {
        sectionSwipeOffset = 0
        service.select(target)
        return
    }
    service.select(target)
    sectionSwipeOffset = direction == .next
        ? service.contentSize.width
        : -service.contentSize.width
    withAnimation(.spring(duration: 0.5, bounce: 0.2)) { sectionSwipeOffset = 0 }
}
```

Spring value comes from AUDIT.md section 4: `{ type: "spring", duration: 0.5, bounce: 0.2 }`. Bounce stays in the 0.1–0.3 range. Duration stays in SwiftUI spring form because this repo animates with SwiftUI springs, not CSS.

## Repo conventions to follow

- Springs use SwiftUI form in Notch UI. Exemplar at `Sources/Vorssaint/UI/Notch/NotchSectionsView.swift:65`:
```swift
.animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: first)
```
- Reduced motion branches to no movement. Exemplar at same file. Keep that pattern.
- Haptic stays on commit via `service.provideHapticFeedback()`. Keep that call.

## Steps

1. In `Sources/Vorssaint/UI/Notch/NotchView.swift:15-19`, delete `sectionSwipeActive` and `sectionSwipeSettling`. Keep `sectionSwipeOffset`.
2. Replace `swipeChanged`, `swipeCancelled`, `swipeCommitted` with the target code above.
3. In `sectionTitle` gesture at `Sources/Vorssaint/UI/Notch/NotchView.swift:573-596`, delete every `!sectionSwipeSettling` guard.
4. In `expanded` at `Sources/Vorssaint/UI/Notch/NotchView.swift:395-406`, delete the `!sectionSwipeSettling` guard in `onChange(of: service.selected)`. Keep the offset reset.
5. Delete `NotchSectionSwipeLogic.spring()` at `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:23-25` if nothing else calls it. Use the inline spring from the target code.

## Boundaries

- Do NOT touch `NotchSectionSwipeCatcher` scroll logic in this plan. That is plan 002.
- Do NOT change markup or structure. Motion and state only.
- Do NOT add new dependencies.
- If a step doesn't match the code you find (drift since commit 68df79e8), STOP and report instead of improvising.

## Verification

- **Mechanical**: parse check with `swiftc -parse Sources/Vorssaint/UI/Notch/NotchView.swift Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift`. Expect exit 0.
- **Feel check**: open the island on AI Agents. Drag the title left halfway. Release. Confirm the page returns with one spring. Swipe left fast twice. Confirm the second swipe interrupts the first and never locks out. Reverse mid-motion. Confirm the page reverses at once.
- **Done when**: no `asyncAfter` and no `sectionSwipeSettling` remain in `NotchView.swift`. Rapid title swipes never ignore input.
