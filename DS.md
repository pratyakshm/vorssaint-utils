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

- `NotchClipboardView`, `NotchControlsView`, `NotchMixerView`,
  `NotchSystemView`, rest of `UI/Notch/`.

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
