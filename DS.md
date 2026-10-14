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

## Remaining

### Settings detail pages (shell is done; per-file literals remain)

- `GeneralSettings.swift`, `MonitorSettings.swift`, `EnergySettings.swift`
  (Keep awake + Bluetooth on sleep), `ClipboardSettings.swift`,
  `CommandBarSettings.swift` (rest), `DockSettings.swift`,
  `QuickToolsSettings.swift`, `NotchSettings.swift` + sub-editors
  (`NotchLayoutEditor`, `NotchContentEditor`, `NotchAgentsSettings`,
  `NotchSpringTuner`, `PanelLayoutEditor`), `FeatureHubSettings.swift`
  (Features page), `ShortcutsSettings.swift`, `AdvancedSettings.swift`,
  `AutoQuitSettings.swift`, `URLCleanerSettings.swift`,
  `DisplayBrightnessShortcutControls.swift`, `MonitorAlertsControls.swift`,
  `MonitorPanelConfig.swift`.

### Menu panel sections

- `PanelClipboardView.swift` (+ `ClipboardTextPreview`,
  `ClipboardThumbnailImage`, `ClipboardEntryPreviewSidebar`,
  `ClipboardClearRecentConfirmation`), `QuickTogglesSection.swift`,
  `SystemSection.swift`, `MixerSection.swift`, `NetworkSection.swift`,
  `PowerSection.swift`, `DiskSection.swift`, `BrightnessSection.swift`,
  `MetricDetailView.swift`, `CPUCoreMatrix.swift`, `ProcessUsageRow.swift`,
  `Sparkline.swift`, `KeepAwakeEndTimePicker.swift`,
  `FanControlCurveEditor.swift`, `PanelLayout.swift`.
- NOTE: `ClipboardQuickPanelView.swift` has uncommitted work in the tree
  (2026-10-14) — migrate it after that work lands.

### Command Bar

- `CommandBarView.swift` floor done; `CommandBarDroplet.swift` remaining.

### Dynamic Island / Notch (all 42 files remaining)

- `NotchView.swift`, `NotchSectionsView.swift`, `NotchComponents.swift`,
  `NotchCapsuleViews.swift`, strips (`NotchMusicStrip`,
  `NotchAgentStrip`, `NotchTimerStrip`, `NotchKeepAwakeStrip`,
  `NotchCalendarStrip`), `NotchDownloadsView`, `NotchLyricsView`,
  `NotchQueueView`, `NotchClipboardView`, `NotchControlsView`,
  `NotchMixerView`, `NotchSystemView`, rest of `UI/Notch/`.

### Other active-feature UI

- `UI/KillProcess/`, `UI/CleaningMode/`, `UI/ColorSwatch.swift`,
  `UI/KeepAwakeAutomationView.swift`, `UI/KeepAwakeIconPicker.swift`,
  `UI/MenuBarMetricsPreview.swift` (Menu bar page),
  `UI/Onboarding/` + `UI/UpdateHighlightsView.swift`,
  `UI/SharedUI.swift` (`KeyCap`, notes), `UI/QuickLauncher/`,
  `UI/NonModalAlert.swift`, `UI/OverlayPanel.swift`.

### Disabled on this machine (skip unless re-enabled)

- Switcher, Shelf, Recorder, Screenshot, Scratchpad, RadialMenu,
  Uninstall, Finder extras, Homebrew, Media, CameraPreview, Cleaner,
  PortManager, QuitProtection, SnippetLibraryView, WindowGestureControls.
