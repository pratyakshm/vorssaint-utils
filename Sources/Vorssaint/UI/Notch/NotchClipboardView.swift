// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Raycast-style history: single-line rows with a leading kind icon, the
/// preview truncated to one line, and hover-only actions behind a selected
/// fill, instead of the panel's stacked cards.
struct NotchClipboardView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var pinnedOnly = false
    /// The card the arrow keys chose from the search field, or the top result
    /// of a typed search; Return uses it the way a click would.
    @State private var highlightedID: UUID?
    @State private var hoveredID: UUID?
    @FocusState private var searching: Bool
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    private var entries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query).filter { !pinnedOnly || $0.isPinned }
    }

    /// Moving swaps neighbours in the list, which a search would misreport.
    private var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: query)
    }

    /// The island draws its text in white and never in the accent color, so a
    /// match stands out by weight alone.
    private func searchText(_ string: String, matching tokens: [String]) -> Text {
        SearchHighlightText.text(string, tokens: tokens, fontSize: 12, highlightColor: nil)
    }

    var body: some View {
        VStack(spacing: NotchLayout.rowSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query).textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .accessibilityLabel(text.search)
                NotchIconButton(symbol: "pin", title: text.pinned, selected: pinnedOnly) {
                    pinnedOnly.toggle()
                }
                NotchIconButton(symbol: "trash", title: text.clearRecent) {
                    let ids = history.recentEntriesSnapshot
                    DispatchQueue.main.async {
                        guard NSAlert.confirmAboveIsland(String(format: text.clearRecentConfirmFormat, ids.count),
                                                         message: text.clearRecentConfirmMessage,
                                                         action: text.clearRecent, destructive: true,
                                                         cancel: text.cancel) else { return }
                        history.clearRecent(ids)
                        copiedID = nil
                    }
                }
                .disabled(history.recentEntries.isEmpty)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
                    service.perform { history.showHistoryWindow(preferNotch: false) }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: NotchLayout.clipboardSearchHeight)
            .modifier(NotchControlSurface(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(searching ? 0.34 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: searching)
            .background {
                if !preview {
                    ClipboardSearchKeyMonitor(active: searching) { handleSearchKey($0) }
                        .frame(width: 0, height: 0)
                }
            }
            // Typing filters the history as soon as the page opens, as in Explore.
            .onAppear { if !preview { searching = true } }
            if !enabled, history.entries.isEmpty {
                // The panel offers the switch beside its caption; the page
                // says why it is empty and turns the history on from here.
                VStack(spacing: 10) {
                    NotchEmptyView(symbol: "doc.on.clipboard", message: text.disabled)
                    Button(text.enable) {
                        enabled = true
                        history.syncWithPreferences()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxHeight: .infinity)
            } else if entries.isEmpty {
                NotchEmptyView(symbol: pinnedOnly ? "pin" : "doc.on.clipboard",
                               message: query.isEmpty && !pinnedOnly ? text.empty : text.noResults)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                row(entry, place: index)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: highlightedID) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                    // A copied recent entry moves to the top, so the list
                    // follows it and the tick stays in view.
                    .onChange(of: copiedID) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A new search starts from its top result instead of a row it hid,
        // and a row that leaves the list hands the highlight on the same way.
        .onChange(of: query) { _, _ in highlightedID = searchHighlight(keeping: nil) }
        .onChange(of: pinnedOnly) { _, _ in highlightedID = searchHighlight(keeping: nil) }
        .onChange(of: entries.map(\.id)) { _, _ in highlightedID = searchHighlight(keeping: highlightedID) }
        .onChange(of: service.clipboardPastePress) { _, press in
            guard let press, !preview else { return }
            guard entries.indices.contains(press.index) else {
                NSSound.beep()
                return
            }
            activate(entries[press.index])
        }
        .task(id: copiedID) {
            // The tick confirms one copy; leaving it on the row forever would
            // read as a permanent state instead of an answer.
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    /// Raycast-style row: icon, single-line preview, time/shortcut hint,
    /// hover-only actions, selected fill when highlighted or pinned.
    /// The row itself is a tap surface; inner buttons stay separate so they
    /// keep their own clicks instead of nesting inside an outer Button.
    private func row(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        let selected = highlightedID == entry.id || hoveredID == entry.id
        let showActions = hoveredID == entry.id || highlightedID == entry.id
        return HStack(spacing: 10) {
            Image(systemName: entry.isPinned ? "pin.fill"
                    : entry.kind == .image ? "photo"
                    : entry.kind == .files ? "folder" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(entry.isPinned ? .yellow : .secondary)
                .frame(width: 22, alignment: .center)
            rowPreview(entry)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { activate(entry) }
                .help(permissions.accessibility ? text.clickRowShortcut : text.copy)
            if showActions {
                HStack(spacing: 2) {
                    if entry.kind == .image, AppFeature.screenshot.isAvailable {
                        NotchIconButton(symbol: "pencil", title: text.edit) { history.editImage(entry) }
                    }
                    NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                    title: copiedID == entry.id ? text.copied : text.copy) { copy(entry) }
                    NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                    title: entry.isPinned ? text.unpin : text.pin) {
                        history.togglePin(entry)
                    }
                    NotchIconButton(symbol: "trash", title: text.delete) { remove(entry) }
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    Text(entry.copiedAt, style: .time)
                        .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    if place < 9, service.panelIsKey {
                        Text("⌘\(place + 1)")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    } else if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9)).foregroundStyle(.tertiary.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? .white.opacity(0.1) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.18 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { activate(entry) }
        .onHover { hovering in hoveredID = hovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
        .contextMenu { actions(entry) }
        .accessibilityAction(named: Text(text.moveUp)) { move(entry, .up) }
        .accessibilityAction(named: Text(text.moveDown)) { move(entry, .down) }
    }

    /// Backwards-compatible alias; the island no longer uses cards.
    private func card(_ entry: ClipboardHistoryEntry, place: Int) -> some View {
        row(entry, place: place)
    }

    /// The quick panel's row menu: paste when the app may type, copy, pin,
    /// move within the list and delete.
    @ViewBuilder private func actions(_ entry: ClipboardHistoryEntry) -> some View {
        if permissions.accessibility {
            Button(l10n.s.menuPaste) { paste(entry) }
        }
        Button(text.copy) { copy(entry) }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
        Button(text.moveUp) { move(entry, .up) }
            .disabled(!canReorder || !history.canMove(entry, .up))
        Button(text.moveDown) { move(entry, .down) }
            .disabled(!canReorder || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) { remove(entry) }
    }

    private func searchHighlight(keeping current: UUID?) -> UUID? {
        NotchSupport.searchHighlight(keeping: current, in: entries.map(\.id), query: query)
    }

    /// Up and Down move the highlight while the search field keeps typing;
    /// Return pastes or copies it like a click.
    private func handleSearchKey(_ keyCode: UInt16) -> Bool {
        let ids = entries.map(\.id)
        switch keyCode {
        case 125, 126:
            guard !ids.isEmpty else { return false }
            highlightedID = NotchSupport.steppedItem(from: highlightedID, in: ids, backwards: keyCode == 126)
            return true
        case 36, 76:
            guard let id = NotchSupport.clipboardPasteTarget(highlighted: highlightedID, in: ids),
                  let entry = entries.first(where: { $0.id == id }) else { return false }
            activate(entry)
            return true
        default:
            return false
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        if permissions.accessibility { paste(entry) } else { copy(entry) }
    }

    private func paste(_ entry: ClipboardHistoryEntry) {
        service.collapse()
        history.copyQuickEntry(entry)
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        // A copied recent entry moves to the top, so the second click of a
        // double click would copy whichever entry took its place.
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type),
           event.clickCount > 1 { return }
        history.copy(entry) { copied in
            if copied {
                copiedID = entry.id
            } else {
                NSSound.beep()
            }
        }
    }

    private func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard canReorder, history.canMove(entry, direction) else { return }
        history.move(entry, direction)
    }

    private func remove(_ entry: ClipboardHistoryEntry) {
        if copiedID == entry.id { copiedID = nil }
        history.remove(entry)
    }

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio,
                                        failureText: "\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
            } else {
                searchText("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)", matching: searchTokens)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .files:
            // One image file shows itself; anything else reads as its name
            // or its count, the way the panel lists files.
            if entry.filePaths.count == 1, let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                ClipboardThumbnailImage(source: .file(path: path),
                                        failureText: entry.fileNames.first ?? entry.preview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(path)
            } else {
                // A count of several files is no text the search reads.
                Label {
                    searchText(entry.filePaths.count == 1
                                   ? (entry.fileNames.first ?? entry.preview)
                                   : String(format: text.fileCountFormat, entry.filePaths.count),
                               matching: entry.filePaths.count == 1 ? searchTokens : [])
                } icon: {
                    Image(systemName: "folder")
                }
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .help(entry.filePaths.joined(separator: "\n"))
            }
        case .text:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 12)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                searchText(entry.preview, matching: searchTokens)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Single-line Raycast preview for the row: thumbnail plus name on one
    /// line, never a tall card.
    @ViewBuilder private func rowPreview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .image:
            HStack(spacing: 8) {
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio,
                                            failureText: "")
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                searchText("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)", matching: searchTokens)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .files:
            HStack(spacing: 8) {
                if entry.filePaths.count == 1, let path = entry.filePaths.first,
                   ClipboardImageStore.isImageFile(atPath: path) {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            failureText: "")
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                searchText(entry.filePaths.count == 1
                               ? (entry.fileNames.first ?? entry.preview)
                               : String(format: text.fileCountFormat, entry.filePaths.count),
                           matching: entry.filePaths.count == 1 ? searchTokens : [])
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(entry.filePaths.joined(separator: "\n"))
        case .text:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 12)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                searchText(entry.preview.replacingOccurrences(of: "\n", with: " "), matching: searchTokens)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Reads the arrow keys and Return before the search field's editor does,
/// which would otherwise spend them moving the caret.
private struct ClipboardSearchKeyMonitor: NSViewRepresentable {
    var active: Bool
    var handleKey: (UInt16) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.active = active
        context.coordinator.handleKey = handleKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(active: active, handleKey: handleKey)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var active: Bool
        var handleKey: (UInt16) -> Bool
        private var monitor: Any?

        init(active: Bool, handleKey: @escaping (UInt16) -> Bool) {
            self.active = active
            self.handleKey = handleKey
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, self.active, let window = view?.window, event.window === window,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      [UInt16(125), 126, 36, 76].contains(event.keyCode),
                      let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                      !editor.hasMarkedText() else { return event }
                return self.handleKey(event.keyCode) ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
