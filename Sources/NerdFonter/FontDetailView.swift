import AppKit
import NerdFonterKit
import SwiftUI

struct FontDetailView: View {
    let font: FontFamily
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(font.name).font(.largeTitle.weight(.semibold))
                Text(font.description).foregroundStyle(.secondary)
                Text("\(font.licenseId) · v\(font.version)")
                    .font(.callout).foregroundStyle(.tertiary)
            }

            switch model.preview {
            case .loading(let progress):
                Group {
                    if let progress {
                        ProgressView(value: progress) { Text("Downloading \(font.name)…") }
                            .frame(maxWidth: 260)
                    }
                }
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
}

private struct PreviewView: View {
    let face: FontFace
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Variant", selection: $model.variant) {
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
