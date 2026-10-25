import AppKit
import NerdFonterKit
import SwiftUI

struct FontDetailView: View {
    let font: FontFamily
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                switch model.preview {
                case .loading(let progress):
                    LoadingView(fontName: font.name, progress: progress)
                        .frame(maxWidth: .infinity, minHeight: 240)
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
            .padding(28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// A specimen: the name set in the font itself, once its preview has loaded.
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(font.name)
                        .font(model.selectedPreviewFace.map { Font($0.font(size: 40)) } ?? .system(size: 40, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    FavoriteButton(id: font.id, model: model)
                }
                Text(font.description).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Tag(text: font.licenseId)
                    Tag(text: "v\(font.version)")
                    if let version = model.installed[font.id]?.nerdFontsVersion {
                        Tag(text: "Nerd Fonts \(version)", systemImage: "checkmark.circle.fill")
                    }
                    if let name = model.installedFamilyName {
                        CopyNameButton(name: name)
                    }
                }
            }
            Spacer()
            InstallButton(font: font, model: model)
        }
    }
}

private struct Tag: View {
    let text: String
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: .capsule)
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
                Text(name).font(.system(.caption, design: .monospaced).weight(.medium))
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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
                Text("\(Int(model.previewSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .labelsHidden()

            TerminalCard(face: face, model: model)
            GlyphGrid(face: face)
        }
    }
}

/// The sample as it would look in a terminal: window chrome, a powerline prompt, and editable code.
private struct TerminalCard: View {
    let face: FontFace
    @Bindable var model: AppModel

    var body: some View {
        let font = face.font(size: model.previewSize)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.8)).frame(width: 11, height: 11)
                }
                Spacer()
                Text(face.familyName).font(.caption).foregroundStyle(Theme.Terminal.dim)
                Spacer()
                Color.clear.frame(width: 47, height: 1)  // balances the dots, keeping the name centred
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.prompt).font(Font(font))
                TextEditor(text: $model.previewText)
                    .font(Font(font))
                    .foregroundStyle(Theme.Terminal.foreground)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: editorHeight(lineHeight: Self.lineHeight(of: font)))
                    .padding(.leading, -5)  // TextEditor's own inset; lines up with the prompt
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.Terminal.background, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)  // light caret and selection on the dark card
    }

    /// Tall enough for every line of the sample, plus one to type into.
    private func editorHeight(lineHeight: CGFloat) -> CGFloat {
        let lines = model.previewText.split(separator: "\n", omittingEmptySubsequences: false).count + 1
        return CGFloat(lines) * lineHeight + 10
    }

    private static func lineHeight(of font: CTFont) -> CGFloat {
        ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// `  ~/code/nerd-fonter   main ` in powerline segments.
    private static let prompt: AttributedString = {
        typealias T = Theme.Terminal
        func run(_ text: String, _ foreground: Color, _ background: Color?) -> AttributedString {
            var run = AttributedString(text)
            run.foregroundColor = foreground
            if let background { run.backgroundColor = background }
            return run
        }
        return run(" \u{F07C} ~/code/nerd-fonter ", T.ink, T.blue)
            + run("\u{E0B0}", T.blue, T.green)
            + run(" \u{E0A0} main ", T.ink, T.green)
            + run("\u{E0B0}", T.green, nil)
    }()
}

private struct GlyphGrid: View {
    let face: FontFace

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
            ForEach(PreviewSample.glyphs) { glyph in
                GlyphTile(glyph: glyph, face: face)
            }
        }
    }
}

private struct GlyphTile: View {
    let glyph: PreviewSample.Glyph
    let face: FontFace
    @State private var isHovered = false
    @State private var copiedAt: Date?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(glyph.character, forType: .string)
            copiedAt = .now
        } label: {
            ZStack {
                if copiedAt != nil {
                    Image(systemName: "checkmark").font(.title3).foregroundStyle(.green)
                } else {
                    Text(glyph.character).font(Font(face.font(size: 22)))
                }
            }
            .frame(width: 48, height: 48)
            .background(.quaternary.opacity(isHovered ? 0.9 : 0.35), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(glyph.name) — click to copy")
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { copiedAt = nil }
        }
    }
}
