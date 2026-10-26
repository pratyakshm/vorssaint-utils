// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import SwiftUI

/// The selected entry, laid out like Tinycast's clipboard preview: content
/// at the top, then the bottom-anchored Information block. No sidebar header,
/// divider or footer chrome.
struct ClipboardEntryPreviewSidebar: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var editingEntryID: UUID?
    @State private var draft = ""
    /// Laid out off the main thread for the entry it was made from.
    @State private var prettyJSON: (entry: ClipboardHistoryEntry, text: String)?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry {
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else if entry.kind == .text {
                    textPreview(entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    contentScrollView(entry)
                }
                ClipboardHistoryInfoSection(entry: entry)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, DS.Space.medium)
        // Clearance for the floating footer, so Information sits above it.
        .padding(.bottom, DS.Size.bottomBarHeight)
        .onAppear { beginEditingIfNeeded() }
        .onChange(of: entry?.id) { _, newID in
            if editingEntryID != nil, editingEntryID != newID {
                cancelEditing()
            }
        }
        .onChange(of: editingEntryID) { _, _ in beginEditingIfNeeded() }
        .onDisappear { cancelEditing() }
        .task(id: entry) {
            guard let entry, entry.kind == .text else { return }
            let text = entry.text
            let pretty = await Task.detached(priority: .userInitiated) {
                ClipboardJSONFormat.pretty(text)
            }.value
            guard !Task.isCancelled else { return }
            prettyJSON = pretty.map { (entry, $0) }
        }
    }

    /// One text view for every text entry: JSON laid out after the entry
    /// appears swaps its text and font in place instead of a new view. The
    /// layout depends only on the text, so a pin or a refreshed copy of the
    /// same entry keeps it.
    private func textPreview(_ entry: ClipboardHistoryEntry) -> ClipboardTextPreview {
        let font = NSFont.monospacedSystemFont(ofSize: DS.Font.previewTextSize, weight: .regular)
        guard let pretty = prettyJSON, pretty.entry.id == entry.id, pretty.entry.text == entry.text else {
            return ClipboardTextPreview(text: entry.text, font: font)
        }
        return ClipboardTextPreview(text: pretty.text, font: font)
    }

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func textEditor(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(spacing: DS.Space.small) {
            TextEditor(text: $draft)
                .font(DS.Font.body)
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(DS.Space.small)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                )
                .focused($editorFocused)
                .onExitCommand { cancelEditing() }
                .accessibilityLabel(text.edit)
            HStack(spacing: DS.Space.small) {
                Spacer(minLength: 0)
                Button(text.cancel) { cancelEditing() }
                Button(text.save) { saveEditing(entry) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ClipboardHistoryEditing.canSave(original: entry.text, draft: draft))
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, DS.Space.xxSmall)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.text)
                .font(DS.Font.previewText)
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .image:
            imagePreview(entry)
        case .files:
            filesPreview(entry)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.small) {
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio)
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func filesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.filePaths.count == 1, let path = entry.filePaths.first {
            singleFilePreview(path)
        } else {
            multipleFilesPreview(entry)
        }
    }

    @ViewBuilder
    private func singleFilePreview(_ path: String) -> some View {
        let isImage = ClipboardImageStore.isImageFile(atPath: path)
        let fileName = (path as NSString).lastPathComponent

        VStack(alignment: .leading, spacing: DS.Space.medium) {
            if isImage {
                ClipboardThumbnailImage(source: .file(path: path),
                                        aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1))
            } else {
                HStack(spacing: DS.Space.small) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    Text(fileName)
                        .font(DS.Font.body)
                        .lineLimit(2)
                }
            }

            Text(path)
                .font(DS.Font.previewText)
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .padding(DS.Space.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func multipleFilesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.small) {
            Text(String(format: text.fileCountFormat, entry.filePaths.count))
                .font(DS.Font.panelFloorEmphasis)
                .foregroundStyle(.secondary)

            VStack(spacing: DS.Space.xSmall) {
                ForEach(entry.filePaths, id: \.self) { path in
                    HStack(spacing: DS.Space.xSmall) {
                        if ClipboardImageStore.isImageFile(atPath: path) {
                            ClipboardThumbnailImage(source: .file(path: path, maxPixelSize: 64))
                                .frame(width: 20, height: 20)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail,
                                                 style: .continuous))
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                        Text((path as NSString).lastPathComponent)
                            .font(DS.Font.panelFloor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(DS.Space.small)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            Text(entry.filePaths.joined(separator: "\n"))
                .font(DS.Font.previewText)
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .padding(DS.Space.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Starts from an existing `editingEntryID` too: the Actions menu can ask
    /// for the editor while the preview is still hidden, so the view is born
    /// already editing and `onChange` alone would never seed the draft.
    private func beginEditingIfNeeded() {
        guard let newID = editingEntryID, let entry, entry.id == newID else { return }
        if draft != entry.text { draft = entry.text }
        ClipboardHistoryService.shared.editingEntryID = newID
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        editingEntryID = nil
        ClipboardHistoryService.shared.editingEntryID = nil
        draft = ""
    }

    private func saveEditing(_ entry: ClipboardHistoryEntry) {
        guard ClipboardHistoryService.shared.updateText(entry, to: draft) else { return }
        cancelEditing()
    }
}

/// Screen OCR on an entry the preview is showing, shared with the Actions
/// menu so the feature survives without resting chrome.
enum ClipboardImageTextCopy {
    @MainActor
    static func copyText(for entry: ClipboardHistoryEntry, language: AppLanguage) {
        guard AppFeature.screenOCR.isAvailable, let url = imageURL(for: entry) else { return }
        let strings = L10n.shared.s
        let languages = MediaSupport.recognitionLanguages(for: language.rawValue)
        let removeLineBreaks = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRRemoveLineBreaks)
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) { () -> ScreenTextService.Outcome in
                // Full size, as Screen OCR reads its capture, so small text
                // survives; only a picture past the area bound is scaled down.
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                else { return .empty }
                let maxPixelSize = ClipboardImageRecognition.decodeMaxPixelSize(width: width, height: height)
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return .empty }
                return ScreenTextService.outcome(for: image, detectQRCodes: false,
                                                 removeLineBreaks: removeLineBreaks,
                                                 fallbackLanguages: languages)
            }.value
            // Anything copied while recognition ran is newer than this answer,
            // and Screen OCR turned off drops it.
            guard pasteboardChangeCount == NSPasteboard.general.changeCount,
                  AppFeature.screenOCR.isAvailable else { return }
            if case .text(let recognized) = outcome {
                ScreenTextService.copyToPasteboard(recognized)
                QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrCopied)
            } else {
                QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrNoText)
            }
        }
    }

    /// The picture an image entry or a single copied image file holds.
    static func imageURL(for entry: ClipboardHistoryEntry) -> URL? {
        if entry.kind == .image, let name = entry.imageFile {
            return ClipboardImageStore.directory?.appendingPathComponent(name)
        }
        guard entry.kind == .files, entry.filePaths.count == 1,
              ClipboardImageStore.isImageFile(atPath: entry.filePaths[0]) else { return nil }
        return URL(fileURLWithPath: entry.filePaths[0])
    }
}

/// Tinycast-style "Information" block: Source / Type / Characters+Words (or
/// Dimensions / Size) / Copied. Disk-touching details stay off the row path;
/// this view only reads what the entry already carries, plus file size.
struct ClipboardHistoryInfoSection: View {
    let entry: ClipboardHistoryEntry

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    static let copiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            Text("Information")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: DS.Space.small) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: DS.Space.rowIconGap)
                        if let icon = sourceIcon, row.label == "Source" {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(row.value)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(DS.Font.panelBody)
                    .padding(.vertical, DS.Space.small)
                }
            }
        }
        .padding(.top, DS.Space.medium)
    }

    private var rows: [InfoRow] {
        var rows: [InfoRow] = []
        if let sourceName {
            rows.append(InfoRow(label: "Source", value: sourceName))
        }
        switch entry.kind {
        case .text:
            let isColor = entry.color != nil
            rows.append(InfoRow(label: "Type", value: isColor ? "Color" : "Text"))
            if !isColor {
                rows.append(InfoRow(label: "Characters", value: entry.text.count.formatted()))
                rows.append(InfoRow(label: "Words", value: Self.wordCount(entry.text).formatted()))
            }
        case .image:
            rows.append(InfoRow(label: "Type", value: "Image"))
            if !entry.imageDimensionsLabel.isEmpty {
                rows.append(InfoRow(label: "Dimensions", value: entry.imageDimensionsLabel))
            }
        case .files:
            let path = entry.filePaths.first ?? ""
            let ext = (path as NSString).pathExtension.lowercased()
            rows.append(InfoRow(label: "Type", value: ext.isEmpty ? "File" : ext.uppercased()))
            if entry.filePaths.count == 1 {
                rows.append(InfoRow(label: "Path",
                                    value: (path as NSString).abbreviatingWithTildeInPath))
            } else {
                rows.append(InfoRow(label: "Files", value: entry.filePaths.count.formatted()))
            }
            if let bytes = fileBytes {
                rows.append(InfoRow(label: "Size",
                                    value: Int64(bytes).formatted(.byteCount(style: .file))))
            }
        }
        rows.append(InfoRow(label: "Copied",
                            value: Self.copiedFormatter.string(from: entry.copiedAt)))
        return rows
    }

    private var sourceName: String? {
        guard let bundleID = entry.sourceBundleID else { return nil }
        return InstalledApps.name(for: bundleID)
    }

    private var sourceIcon: NSImage? {
        guard let bundleID = entry.sourceBundleID,
              let url = InstalledApps.url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var fileBytes: Int? {
        guard entry.kind == .files, entry.filePaths.count == 1 else { return nil }
        return try? FileManager.default
            .attributesOfItem(atPath: entry.filePaths[0])[.size] as? Int
    }

    private nonisolated static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let separator = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !separator, !inWord { count += 1 }
            inWord = !separator
        }
        return count
    }
}
