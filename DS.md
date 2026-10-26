# DS — Central Design System Migration Log

Tokens live in `Sources/Vorssaint/UI/Theme.swift` (`DS.Font`, `DS.Space`,
`DS.Radius`). Rule: new and touched views use `DS`; untouched views keep
their literals until their panel is adopted. Smallest body text allowed is
11pt (`DS.Font.panelFloor`).

Token defaults (2026-10-14): cardTitle 15 semibold, rowTitle 14, body 13.5,
caption 12.5, footnote 11.5, badge 10 bold, section 11 semibold,
panelTitle 12.5 semibold, panelBody 12, panelFloor 11 / 11 semibold,
rowIcon 13 semibold. Spaces: card 18, cardStack 16, rowGap 14,
rowTextStack 4, rowTitleGap 8. Radius card 14.

Append one timestamped entry per migration slice below.

## Log

### 2026-10-27 — clipboard quick panel rebuilt to Tinycast palette metrics

Done (`./build.sh` release bundle OK; `./build.sh --test` compiles and
clipboard suites pass — 17 unrelated dock-preview/switcher scroll checks
fail on this display):

- `UI/MenuPanel/ClipboardQuickPanelView.swift` — Tinycast header (16pt
  gutter, back chevron, 20pt search, filter control), fixed 290pt list |
  1pt separator | preview, 26pt rows with 10pt icon gap and 6pt vertical
  padding, section headers at 11pt medium, floating 52pt footer with
  circular app menu and frosted capsule (`Paste to <App>` + `↵`,
  `Actions` + `⌘K`), custom in-panel filter/actions/app popovers.
- `UI/MenuPanel/ClipboardEntryPreviewSidebar.swift` — chrome-free preview:
  12pt horizontal padding, monospaced top-aligned selectable text, bottom
  Information block with Source/Type/Characters/Words/Copied rows at 12pt
  and 8pt row padding; `editingEntryID` binding replaces `isEditing`;
  `ClipboardImageTextCopy` keeps OCR reachable from Actions.
- `UI/MenuPanel/ClipboardTextPreview.swift` — zero text-container inset
  and line-fragment padding; default font is now
  `DS.Font.previewTextSize` monospaced.
- `UI/Theme.swift` — search/bar/section/menu/keycap/header/preview font
  tokens, micro/row-icon spacing, panel/thumbnail/keycap/bar/menu radii,
  `Size` metrics, and selection/hover/batch surface fills.
- `Services/Clipboard/ClipboardHistoryService.swift` — quick type filter,
  Actions request and menu-open state, Escape closes a menu first,
  `pasteTargetDisplayName`, transparent window with 26pt content radius.
- `Services/Clipboard/ClipboardHistorySupport.swift` — `ClipboardQuickTypeFilter`.
- `Tests/ClipboardFeatureTests.swift` — preview fixture gains the filter
  property used by `filteredQuickEntries`.

Clipboard files stay under Menu panel Done; no Remaining entries moved.

### 2026-10-21 — clipboard quick panel: proportional columns + sidebar stragglers

Done (`swiftc -parse` OK; `./build.sh --test` exits 0 — 112,766 checks,
preference cleanup, uninstall spaces, developer isolation OK):

- `UI/MenuPanel/ClipboardQuickPanelView.swift` — preview pane fixed
  `width: 280` → proportional `GeometryReader` split: list 35%,
  sidebar 65% of the window when the preview is open; list alone still
  spans the full width. Window minimum-size math
  (`ClipboardHistoryWindowSizing`) unchanged.
- `UI/MenuPanel/ClipboardEntryPreviewSidebar.swift` — Information header
  `.subheadline.weight(.medium)` → `DS.Font.panelTitle`; info rows
  `.callout` → `DS.Font.panelBody` (exact 12pt match).

Kept on purpose: `ClipboardTextPreview` default
`systemFont(ofSize: 12)` and JSON's `monospacedSystemFont(ofSize: 11.5)`
(AppKit `NSFont`, monospaced design has no DS token); the path rows'
`.system(size: 11, design: .monospaced)` (same), search field's 20pt and
empty-state's 27pt glyph (search-field/display sizes, kept by the second
slice), thumbnail `cornerRadius: 6`.

### 2026-10-14 — DS created, first slice (most-used screens)

Done:

- `UI/Theme.swift` — added `DS`; `sectionTitle` 10pt → `DS.Font.section`
  (11pt); `panelCard` padding 10 → 12, radius 10 → 14.
- `UI/Settings/SettingsCard.swift` — card title → 15pt, row titles 14pt,
  captions → 12.5pt, badge 8 → 10pt, wider stacks. Covers ALL Settings
  pages via the shared shell.
- `UI/CommandBar/CommandBarView.swift` — 8/8.5/9pt floor → 11pt,
  9.5 → 11.5pt.
- `UI/MenuPanel/MenuPanelView.swift` — same floor lift; `PanelRowMetrics`
  iconSpacing 9 → 12, insets 10/8 → 12.
- `UI/MenuPanel/FanControlSection.swift` — badge 7.5 → 10pt,
  status 10 → 12pt, tight stacks widened.
- `UI/Settings/CommandBarSettings.swift` — last 9pt straggler → 11pt.

Commit `2ea65f8e`, pushed to `main`. Full `swift build` not verified in
this environment (pre-existing `SwiftUIMacros` toolchain failure, clean
tree fails identically); files pass `swiftc -parse`.

### 2026-10-14 — second slice (settings details, clipboard panel, notch, menu sections)

Done (token swaps only, no layout reflows; each file passes
`swiftc -parse`):

- Settings: `GeneralSettings.swift`, `MonitorSettings.swift`,
  `MonitorAlertsControls.swift`, `MonitorPanelConfig.swift`,
  `EnergySettings.swift` (Keep awake + Bluetooth on sleep),
  `CommandBarSettings.swift` (rest).
- Clipboard panel: `PanelClipboardView.swift`,
  `ClipboardTextPreview.swift`, `ClipboardThumbnailImage.swift`,
  `ClipboardEntryPreviewSidebar.swift`. `ClipboardClearRecentConfirmation.swift`
  reviewed — alert-only, no literals.
- Command Bar: `CommandBarDroplet.swift` reviewed — AppKit/CALayer only,
  no SwiftUI font/spacing literals.
- Notch core: `NotchView.swift`, `NotchSectionsView.swift`,
  `NotchComponents.swift`, `NotchCapsuleViews.swift`.
- Notch strips: `NotchMusicStrip`, `NotchAgentStrip`, `NotchTimerStrip`,
  `NotchCalendarStrip`, `NotchDownloadsView`, `NotchLyricsView`,
  `NotchQueueView`. `NotchKeepAwakeStrip` reviewed — no hardcoded literals.
- Menu sections: `QuickTogglesSection.swift`, `SystemSection.swift`,
  `MixerSection.swift`, `NetworkSection.swift`, `PowerSection.swift`,
  `DiskSection.swift`, `BrightnessSection.swift`, `MetricDetailView.swift`,
  `CPUCoreMatrix.swift`, `ProcessUsageRow.swift`.
- Other: `KillProcess/KillProcessView.swift`,
  `CleaningMode/CleaningOverlayView.swift`,
  `KeepAwakeAutomationView.swift`, `KeepAwakeIconPicker.swift`,
  `Onboarding/OnboardingView.swift`, `Onboarding/WhatsNewView.swift`,
  `UpdateHighlightsView.swift`, `SharedUI.swift`,
  `MenuBarMetricsPreview.swift` (chrome only — miniature renderer sizes
  kept pixel-exact). `ColorSwatch.swift` reviewed — no literals.

Skipped: `Settings/ClipboardSettings.swift` (foreign uncommitted work at
the time; landed as `26e52ce0` mid-slice — still to migrate).
Full `swift build` not verified (same pre-existing `SwiftUIMacros`
CommandLineTools-only toolchain failure); all touched files pass
`swiftc -parse`.

### 2026-10-15 — test target repair (DS tokens in generated fixtures)

Done:

- `Tests/generate_sources.py` — extracts `enum DS` from
  `UI/Theme.swift` into `build/generated-tests/DSTokens.swift`. The test
  target compiles extracted views (`NotchActivityPicker`, `NotchRail`,
  `UpdateHighlightsView`, `SettingsCard` family) without the full Theme,
  which needs app services. Without this, `./build.sh --test` failed with
  `cannot find 'DS' in scope` (plus cascading `ForEach`/`==` errors on
  `NotchCompactActivity`) since the first DS slice.
- `Tests/NotchSettingsChoiceTests.swift` — hardcoded card padding 16 →
  `DS.Space.card` (4 spots: text column, content bounds, beside-title
  check). Card padding is 18 under DS, so every row measured 2pt off.
- `Tests/FeatureCatalogTests.swift` — onboarding `VStack` spacing check
  accepts `DS.Space.rowGap` as well as the literal 14 (same value).

Verified: `./build.sh --test` exits 0 — TESTS OK (115928 checks),
preference cleanup, uninstall spaces and developer isolation all OK.

### 2026-10-14 — third slice (clipboard leftovers, panel tail, launcher)

Done (token swaps only, no layout reflows; each file passes
`swiftc -parse`):

- `Settings/ClipboardSettings.swift` (11× `.caption` → `DS.Font.caption`,
  1× `.caption2` → `footnote`; Form shell owns spacing).
- `MenuPanel/ClipboardQuickPanelView.swift` (sub-11pt → floor, 11.5 →
  footnote, 12 → panelBody, row radius → `DS.Radius.row`; search-field
  and glyph display sizes kept).
- `MenuPanel/Sparkline.swift` (ceiling label 9pt → floor; chart geometry
  kept pixel-exact), `MenuPanel/PanelLayout.swift`,
  `MenuPanel/KeepAwakeEndTimePicker.swift` (wheel digits kept),
  `MenuPanel/FanControlCurveEditor.swift` (graph geometry kept).
- `QuickLauncher/QuickLauncherView.swift` (18 hardcoded fonts swapped;
  frames/chrome kept). `OverlayPanel.swift` and `NonModalAlert.swift`
  reviewed — AppKit-only, no SwiftUI literals.
- `Settings/DockSettings.swift`.

Full `swift build` not verified (same pre-existing `SwiftUIMacros`
toolchain failure); all touched files pass `swiftc -parse`.

### 2026-10-15 — command-bar invoke transition editor (new view, DS from birth)

Done (new view uses `DS` throughout; `CommandBarSettings.swift` addition
uses the same tokens; each file passes `swiftc -parse`):

- `UI/Settings/CommandBarTransitionEditor.swift` (new) — open/close layer
  stacks, per-layer kind/duration/curve/spring controls, droplet pace,
  Copy config (JSON) + Import, Preview, Reset. Fonts `DS.Font.*`,
  spacing `DS.Space.*`, row radius `DS.Radius.row`.
- `UI/Settings/CommandBarSettings.swift` — new "Invoke transition" section
  (Edit sheet + Copy config), `DS.Space.medium` / `DS.Font.caption`.

Verified: `./build.sh --test` matches the clean-tree baseline — every
suite passes except the pre-existing environment failures in `notch`
(`NotchCompactTests` rail rows), `dock-autohide` and `switcher`
(`SwitcherScrollTests`), which fail identically with these changes
stashed. `command-bar` OK (768 checks, incl. new
`CommandBarAppearTransitionTests`), `repository` OK (314 checks).

### 2026-10-18 — upstream merge (109 commits to `b67dcf1c`): DS held on the touched panels

Resolved (merge commit `4170078e` on `merge/upstream-oct18`; fork behaviors
kept, upstream's new layouts adopted): `NotchView`, `NotchService`,
`NotchClipboardView`, `NotchMusicView`, `NotchComponents`,
`NotchDownloadsView`, `NotchLockScreenView`, `NotchAgentsView`,
`NotchAgentsSettings`, `NotchService`, `MixerSection`, `PowerSection`,
`QuickLauncherView`, `AgentLogParser`, `AgentUsageService`,
`CommandBarService`, tests/README/build script.

- Upstream's rewrites adopted and re-tokened on the way in:
  `MixerSection` (3 literals → `DS.Font.panelFloorEmphasis`), `PowerSection`
  (2 → `DS.Space.xSmall`, + new peripheral-battery row), `QuickLauncherView`
  (1 → `DS.Space.medium`, band chrome by upstream). All three stay
  token-clean (76/27/38 DS refs, 0 literals).
- `NotchView` resolved to upstream's #3140 island layout with the fork's
  section-title swipe re-attached, DS tokens in the re-inserted pieces
  (0 literals; `expansionGeometry.headerTitleFont` was upstream-deleted —
  fork's header title now `DS.Font.cardTitle`).
- Back to literals after upstream's rewrites (re-migration pending):
  `NotchClipboardView` (15, was already Remaining), `NotchMusicView` (12,
  upstream head/transport rewrite — new in Remaining), `NotchComponents`
  (5, regressed from the second slice's rail work).
- `build.sh`/test target: `Harness/CursorReader.swift` (fork's Cursor
  parser, now behind upstream's harness-reader protocol) added to
  `TEST_SOURCES`; `Tests/mutation_checks.py` progress-filter check pinned
  to the fork's cursor-excluding variant.

Verified: `./build.sh --test` exits 0 — TESTS OK (112,707 checks),
preference cleanup, uninstall spaces and developer isolation OK. All
suites pass on this machine, including the previously flaky `notch`
(66,200 checks), `dock-autohide` and `switcher`.

### 2026-10-20 — fourth slice (notch clipboard page)

Done (token swaps only, no layout reflows; file passes
`swiftc -parse`; `./build.sh --test` exits 0 — TESTS OK
(112,766 checks), preference cleanup, uninstall spaces and
developer isolation OK):

- `UI/Notch/NotchClipboardView.swift` — all font literals swapped:
  sub-11pt floors (9/9.5/10) → `DS.Font.panelFloor`, 11 → `panelFloor`,
  12 → `panelBody`, preview text 13 → `rowTitle`, kind icons 13 →
  `rowIcon`. Radii: card/search/open backing 14 → `DS.Radius.card`,
  selected row highlight 10 → `DS.Radius.row`. Spacing exact matches:
  6 → `DS.Space.xSmall`, 8 → `DS.Space.small`, search-field inset 12 →
  `DS.Space.medium`.
- `SearchHighlightText` calls keep their raw `fontSize` values
  (panel-cluster precedent: the matched-range attributed font pins the
  highlight to the row's nominal size; the outer token governs).

Kept on purpose (no token at these values, or pinned geometry): row
paddings of 10 (text starts 10 pt in, which `openTextWidth()` derives
and the open-card backing's edge rests on), 2/5/7-pt stacks, thumbnail
clips at radius 6, and the empty-state VStack's 10.

## Remaining

### Settings detail pages (shell is done; per-file literals remain)

- `QuickToolsSettings.swift`,
  `NotchSettings.swift` + sub-editors (`NotchLayoutEditor`,
  `NotchContentEditor`, `NotchAgentsSettings`, `NotchSpringTuner`,
  `PanelLayoutEditor`), `FeatureHubSettings.swift` (Features page),
  `ShortcutsSettings.swift`, `AdvancedSettings.swift`,
  `AutoQuitSettings.swift`, `URLCleanerSettings.swift`,
  `DisplayBrightnessShortcutControls.swift`.

### Menu panel sections

Done — all migrated (`PanelClipboardView` + previews,
`ClipboardQuickPanelView`, `QuickToggles`, `System`, `Mixer`, `Network`,
`Power`, `Disk`, `Brightness`, `MetricDetailView`, `CPUCoreMatrix`,
`ProcessUsageRow`, `Sparkline`, `KeepAwakeEndTimePicker`,
`FanControlCurveEditor`, `PanelLayout`).

### Command Bar

Done — `CommandBarView.swift` floor plus `CommandBarDroplet.swift`
reviewed (no SwiftUI literals).

### Dynamic Island / Notch (core + strips done)

- `NotchMusicView`, `NotchControlsView`, `NotchMixerView`,
  `NotchSystemView`, rest of `UI/Notch/`. `NotchComponents` re-picked up 5
  literals in the 2026-10-18 upstream merge — re-migrate with these.

### Other active-feature UI

Done — `UI/KillProcess/`, `UI/CleaningMode/`, `UI/ColorSwatch.swift`
(reviewed, no literals), `UI/KeepAwakeAutomationView.swift`,
`UI/KeepAwakeIconPicker.swift`, `UI/MenuBarMetricsPreview.swift`,
`UI/Onboarding/` + `UI/UpdateHighlightsView.swift`, `UI/SharedUI.swift`,
`UI/QuickLauncher/QuickLauncherView.swift`, `UI/NonModalAlert.swift`
(reviewed, AppKit-only), `UI/OverlayPanel.swift` (reviewed, AppKit-only).

### Disabled on this machine (skip unless re-enabled)

- Switcher, Shelf, Recorder, Screenshot, Scratchpad, RadialMenu,
  Uninstall, Finder extras, Homebrew, Media, CameraPreview, Cleaner,
  PortManager, QuitProtection, SnippetLibraryView, WindowGestureControls.
