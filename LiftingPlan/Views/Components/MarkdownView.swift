import SwiftUI

/// Markdown, drawn.
///
/// **What it does.** Renders a note the coach wrote — headings as headings,
/// paragraphs as paragraphs — with this app's type roles rather than the
/// system's defaults.
///
/// **It renders and never parses.** Nothing is read *out* of the text: this
/// splits on blank lines to give paragraphs their spacing and hands each one to
/// `AttributedString`, which is what turns emphasis and links into type. No
/// value is extracted, because the moment one has to be, it belongs in a table.
///
/// **What it depends on.** `Typography` and `Spacing`. It holds no state.
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

    /// The note split into paragraphs and headings — one drawn thing each.
    private var blocks: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func line(_ block: String) -> some View {
        if block.hasPrefix("## ") {
            SectionHeading(String(block.dropFirst(3)))
        } else if block.hasPrefix("# ") {
            Text(String(block.dropFirst(2)))
                .font(.supersetHeading)
                .foregroundStyle(Palette.ink)
        } else {
            Text(attributed(block))
                .font(.supersetBody)
                .foregroundStyle(Palette.ink)
        }
    }

    /// The paragraph with its emphasis, or as plain text when it will not parse.
    ///
    /// Falling back rather than refusing: this is prose a person wrote, and a
    /// stray asterisk should reach him as an asterisk rather than as an empty
    /// screen.
    private func attributed(_ block: String) -> AttributedString {
        (try? AttributedString(
            markdown: block,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(block)
    }
}
