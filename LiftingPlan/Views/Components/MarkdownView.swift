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
/// **What it depends on.** `Palette`, `Spacing` and the type ramp. It holds no
/// state, and it draws its own headings rather than borrowing the list one — see
/// `line(_:)` for why that mattered.
struct MarkdownView: View {

    let text: String

    var body: some View {
        // **Spacing is per block, not one gap repeated.** An even rhythm put the
        // same air above a heading as below it, so a heading floated between the
        // passage it ended and the one it introduced and the page read as a list
        // of unrelated lines. A heading belongs to what follows it: it gets the
        // major gap above and its prose sits close underneath.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                line(block)
                    .padding(.top, index == 0 ? 0 : space(above: block))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One drawn thing.
    ///
    /// **`#` and `##` are one case, deliberately.** They drew as two and looked
    /// identical, because both resolved to the same type role — a distinction
    /// the code claimed and the screen did not. These documents already carry
    /// their one title in the sheet's navigation bar, which is why the templates
    /// stopped writing an `#` of their own; anything the coach heads a passage
    /// with is a section within that, whatever depth he happens to type.
    private enum Block {
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
                blocks.append(.heading(String(trimmed.dropFirst(2))))
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    /// What separates this block from the one above it. Never applied to the
    /// first, which sits against the top of whatever presents it.
    private func space(above block: Block) -> CGFloat {
        switch block {
        case .heading: Spacing.major
        case .paragraph: Spacing.snug
        }
    }

    /// **A heading is drawn here rather than by `SectionHeading`.** That one is a
    /// list component: it carries `PanelMetrics.inset` so a name and the edge of
    /// the panel it names share a line, plus `listRow` insets, background and
    /// separator. Inside this scroll view the list modifiers did nothing and the
    /// inset stacked on top of the container's own padding — so every heading on
    /// the lifter's page and the programme's sat indented from the prose beneath
    /// it, and nothing on either screen shared a left edge. One component, two
    /// screens, one defect.
    @ViewBuilder
    private func line(_ block: Block) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.supersetHeading)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
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
