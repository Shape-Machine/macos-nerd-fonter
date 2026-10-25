import AppKit
import NerdFonterKit
import SwiftUI

struct FontDetailView: View {
    let font: FontFamily
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(font.name).font(.largeTitle.weight(.semibold))
                        FavoriteButton(id: font.id, model: model)
                        if let name = model.installedFamilyName {
                            CopyNameButton(name: name)
                                .padding(.leading, 4)
                        }
                    }
                    Text(font.description).foregroundStyle(.secondary)
                    Text(details).font(.callout).foregroundStyle(.tertiary)
                }
                Spacer()
                InstallButton(font: font, model: model)
            }

            switch model.preview {
            case .loading(let progress):
                LoadingView(fontName: font.name, progress: progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't Load Preview", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try Again") { Task { await model.loadPreview() } }
                }
            case .loaded:
                if let face = model.previewFace {
                    PreviewView(face: face, model: model)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(font.name)
    }

    /// "OFL-1.1 · v2.304", plus the installed Nerd Fonts release when known.
    private var details: String {
        var parts = [font.licenseId, "v\(font.version)"]
        if let version = model.installed[font.id]?.nerdFontsVersion {
            parts.append("Installed: Nerd Fonts \(version)")
        }
        return parts.joined(separator: " · ")
    }
}

struct FavoriteButton: View {
    let id: FontFamily.ID
    let model: AppModel

    var body: some View {
        let isFavorite = model.favorites.contains(id)
        Button { model.toggleFavorite(id) } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// The exact family name of the shown variant, e.g. "JetBrainsMono Nerd Font Mono". Click to copy.
private struct CopyNameButton: View {
    let name: String
    /// Set on each click; restarting the task below restarts the timer, so a later click never
    /// has its checkmark cleared by an earlier one.
    @State private var copiedAt: Date?
    private var copied: Bool { copiedAt != nil }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(name, forType: .string)
            copiedAt = .now
        } label: {
            HStack(spacing: 6) {
                Text(name).font(.system(.callout, design: .monospaced))
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Copy the font name for your editor or terminal settings")
        .onChange(of: name) { copiedAt = nil }
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copiedAt = nil }
        }
    }
}

private struct InstallButton: View {
    let font: FontFamily
    let model: AppModel

    var body: some View {
        Group {
            switch model.operations[font.id] {
            case .installing(let progress?) where progress < 1, .updating(let progress?) where progress < 1:
                ProgressView(value: progress) { Text("Downloading…") }
                    .frame(width: 120)
            case .installing:
                ProgressView { Text("Installing…") }.controlSize(.small)
            case .updating:
                ProgressView { Text("Updating…") }.controlSize(.small)
            case .uninstalling:
                ProgressView { Text("Uninstalling…") }.controlSize(.small)
            case nil:
                if let installation = model.installed[font.id] {
                    if installation.isSystemWide {
                        Label("Installed for All Users", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                            .help("Installed in /Library/Fonts. Remove it in Finder or Font Book.")
                    } else {
                        HStack {
                            Button("Uninstall") { Task { await model.uninstall(font) } }
                                .help("Move this family's \(installation.files.count) files to the Trash")
                            if model.isUpdateAvailable(font.id) {
                                Button("Update") { Task { await model.update(font) } }
                                    .buttonStyle(.borderedProminent)
                                    .help("Nerd Fonts \(installation.nerdFontsVersion ?? "") → \(model.latestVersion ?? "")")
                            }
                        }
                    }
                } else {
                    Button("Install") { Task { await model.install(font) } }
                        .buttonStyle(.borderedProminent)
                        .help("Install all variants for your user account")
                }
            }
        }
        .controlSize(.large)
        .font(.callout)
    }
}

/// Download progress while bytes arrive; a spinner while connecting or unpacking.
/// The spinner waits a moment so cached previews, which load almost instantly, don't flash.
private struct LoadingView: View {
    let fontName: String
    let progress: Double?
    @State private var isVisible = false

    var body: some View {
        // Color.clear keeps this a real view even when nothing is shown, so `.task` runs.
        ZStack {
            Color.clear
            if let progress, progress < 1 {
                ProgressView(value: progress) { Text("Downloading \(fontName)…") }
                    .frame(maxWidth: 260)
            } else if isVisible {
                ProgressView { Text(progress == nil ? "Loading preview…" : "Preparing preview…") }
            }
        }
        .foregroundStyle(.secondary)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            isVisible = true
        }
    }
}

private struct PreviewView: View {
    let face: FontFace
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Variant", selection: $model.shownVariant) {
                    ForEach(model.variants) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                if model.baseNames.count > 1 {
                    Picker("Typeface", selection: $model.baseName) {
                        ForEach(model.baseNames, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }

                Spacer()

                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                Slider(value: $model.previewSize, in: 10...40).frame(width: 140)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
            .labelsHidden()

            TextEditor(text: $model.previewText)
                .font(Font(face.font(size: model.previewSize)))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))

            GlyphGrid(face: face)
        }
    }
}

private struct GlyphGrid: View {
    let face: FontFace
    @State private var copied: PreviewSample.Glyph.ID?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
            ForEach(PreviewSample.glyphs) { glyph in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(glyph.character, forType: .string)
                    copied = glyph.id
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if copied == glyph.id { copied = nil }
                    }
                } label: {
                    ZStack {
                        if copied == glyph.id {
                            Image(systemName: "checkmark").font(.title3).foregroundStyle(.green)
                        } else {
                            Text(glyph.character).font(Font(face.font(size: 22)))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(glyph.name) — click to copy")
            }
        }
    }
}
