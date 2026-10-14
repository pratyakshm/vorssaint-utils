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

## Remaining

### Settings detail pages (shell is done; per-file literals remain)

- `ClipboardSettings.swift` (foreign work landed as `26e52ce0` — migrate
  next), `DockSettings.swift`, `QuickToolsSettings.swift`,
  `NotchSettings.swift` + sub-editors (`NotchLayoutEditor`,
  `NotchContentEditor`, `NotchAgentsSettings`, `NotchSpringTuner`,
  `PanelLayoutEditor`), `FeatureHubSettings.swift` (Features page),
  `ShortcutsSettings.swift`, `AdvancedSettings.swift`,
  `AutoQuitSettings.swift`, `URLCleanerSettings.swift`,
  `DisplayBrightnessShortcutControls.swift`.

### Menu panel sections

- `Sparkline.swift`, `KeepAwakeEndTimePicker.swift`,
  `FanControlCurveEditor.swift`, `PanelLayout.swift`.
- NOTE: `ClipboardQuickPanelView.swift` foreign work landed as `26e52ce0`
  — migrate it next.

### Command Bar

Done — `CommandBarView.swift` floor plus `CommandBarDroplet.swift`
reviewed (no SwiftUI literals).

### Dynamic Island / Notch (core + strips done)

- `NotchClipboardView`, `NotchControlsView`, `NotchMixerView`,
  `NotchSystemView`, rest of `UI/Notch/`.

### Other active-feature UI

- `UI/QuickLauncher/`, `UI/NonModalAlert.swift`, `UI/OverlayPanel.swift`.

### Disabled on this machine (skip unless re-enabled)

- Switcher, Shelf, Recorder, Screenshot, Scratchpad, RadialMenu,
  Uninstall, Finder extras, Homebrew, Media, CameraPreview, Cleaner,
  PortManager, QuitProtection, SnippetLibraryView, WindowGestureControls.
