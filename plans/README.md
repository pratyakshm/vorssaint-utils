# Section swipe motion plans

Recommended order: 002, then 001, then 003. Plan 002 removes inputs first. Plan 001 fixes timing on the one input that remains. Plan 003 sets final values.

| Number | Title | Severity | Status | Depends on |
|---|---|---|---|---|
| 001 | Interruptible single-spring swipe | HIGH | DONE | 002 |
| 002 | Single gesture input | HIGH | DONE | none |
| 003 | Apple motion values | MEDIUM | DONE | 001 |

## Findings table

| # | Severity | Category | Location | Finding | Fix summary |
|---|---|---|---|---|---|
| 1 | HIGH | Interruptibility | `Sources/Vorssaint/UI/Notch/NotchView.swift:356` | Two chained `asyncAfter` calls with `sectionSwipeSettling` lock out input for 0.4 seconds | One spring, no timers, plan 001 |
| 2 | HIGH | Cohesion | `Sources/Vorssaint/UI/Notch/NotchView.swift:571` | Three input paths for one action: scroll, swipe, drag | Keep scroll only, plan 002 |
| 3 | MEDIUM | Easing | `Sources/Vorssaint/UI/Notch/NotchSectionSwipe.swift:23` | Two hand-picked springs with no token | Apple spring duration 0.5 bounce 0.2, plan 003 |
| 4 | MEDIUM | Performance | `Sources/Vorssaint/UI/Notch/NotchView.swift:392` | Offset plus opacity is correct, but per-tick state updates re-evaluate the full body | Keep transform and opacity only, plan 001 |
| 5 | LOW | Accessibility | `Sources/Vorssaint/UI/Notch/NotchView.swift:324` | Reduce Motion path exists and is correct | Keep and verify in each plan |

## Missed opportunities

- Velocity dismissal uses distance only. A fast flick short of 60 points should commit. Plan 002 keeps the scroll path simple on purpose. Add velocity later if feel tests ask for it.
- Title parallax at 0.18x is subtle and correct. Keep it. Do not add stagger or blur.

## How to execute

Skill rules forbid source edits in this audit step. Run each plan with any agent. Or run `improve-animations execute plans/002-single-gesture-input.md`, then 001, then 003.
