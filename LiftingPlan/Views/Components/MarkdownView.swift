import SwiftUI

/// Markdown, drawn.
///
/// **What it does.** Renders a note the coach wrote — headings as headings,
/// paragraphs as paragraphs — with this app's type roles rather than the
/// system's defaults.
///
/// **It renders and never parses.** Nothing is read *out* of the text. No value
/// is extracted, because the moment one has to be, it belongs in a table.
///
/// **What it depends on.** `SectionHeading`, `Palette` and `Spacing`. It holds
/// no state.
struct MarkdownView: View {

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                line(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One drawn thing.
    private enum Block {
        case title(String)
        case heading(String)
        case paragraph(String)
    }

    /// The note as the things it draws.
    ///
    /// **Split by line, not by blank line.** Splitting on blank lines put a
    /// heading and the paragraph beneath it in one block whenever the coach did
    /// not leave a line between them — which is how anyone writes markdown. The
    /// whole block then matched `## ` and drew as a heading, so every word of
    /// his prose came out bold and title-sized.
    ///
    /// **A paragraph's lines are joined with spaces**, which is what a single
    /// newline means in markdown. Preserving them broke sentences wherever the
    /// source happened to wrap — *"Blocks run three / sessions"* — which is the
    /// file's line width showing through onto a screen that has its own.
    private var blocks: [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flush()
                blocks.append(.title(String(trimmed.dropFirst(2))))
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    @ViewBuilder
    private func line(_ block: Block) -> some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(.supersetHeading)
                .foregroundStyle(Palette.ink)
        case .heading(let text):
            SectionHeading(text)
        case .paragraph(let text):
            Text(attributed(text))
                .font(.supersetBody)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The paragraph with its emphasis, or as plain text when it will not parse.
    ///
    /// Falling back rather than refusing: this is prose a person wrote, and a
    /// stray asterisk should reach him as an asterisk rather than as an empty
    /// screen.
    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
