import SwiftUI
import PDFKit

// MARK: - Day Mode Reading View (Deep Forest "Clean Sanctuary" design)
//
// Light reading mode. Warm cream background, dark text, editorial layout.
// Uses PagedContentView for shared scroll/pagination logic.

struct DayModeReadingView: View {
    let document: PDFDocument?
    let theme: Theme
    let book: Book
    let fontSize: Double
    let currentPageIndex: Int
    let savedBlockID: Int
    @Binding var goToPageIndex: Int?
    let chapters: [Chapter]
    let currentChapter: Chapter?
    let onPageChange: (Int, Int) -> Void
    let onTap: () -> Void
    let onAIAction: (AIActionType, String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            theme.dayBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                dayTopBar

                PagedContentView(
                    document: document,
                    currentPageIndex: currentPageIndex,
                    savedBlockID: savedBlockID,
                    goToPageIndex: $goToPageIndex,
                    onPageChange: onPageChange,
                    onTap: onTap,
                    scrollViewID: "\(fontSize)",
                    contentPadding: EdgeInsets(top: 0, leading: 24, bottom: 40, trailing: 24),
                    backgroundColor: .clear,
                    progressTint: theme.dayAccent,
                    header: { chapterHeader.padding(.horizontal, 24).padding(.bottom, 24) },
                    blockContent: { block, screenWidth in
                        dayBlockView(block, contentWidth: screenWidth - 48)
                    }
                )
            }
        }
    }

    // MARK: - Top Bar

    private var dayTopBar: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(theme.dayTextSecondary)

            Text(theme.dayTitle)
                .font(theme.headlineFont(size: 18))
                .foregroundStyle(theme.dayAccent)

            Spacer()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(theme.dayTextSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Chapter Header

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let chapter = currentChapter {
                Text("CHAPTER \(romanNumeral(chapter.id + 1))")
                    .font(theme.captionFont(size: 12))
                    .foregroundStyle(theme.dayTextSecondary)
                    .kerning(3)
                    .padding(.top, 24)

                Text(chapter.title)
                    .font(theme.headlineFont(size: 32))
                    .foregroundStyle(theme.dayTextPrimary)
            } else {
                Text(book.title)
                    .font(theme.headlineFont(size: 32))
                    .foregroundStyle(theme.dayTextPrimary)
                    .padding(.top, 24)
            }

            Rectangle()
                .fill(theme.dayDivider)
                .frame(height: 1)

            HStack(spacing: 12) {
                Circle()
                    .fill(theme.dayDivider)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String((book.author ?? "A").prefix(1)).uppercased())
                            .font(theme.labelFont(size: 16))
                            .foregroundStyle(theme.dayTextSecondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.author ?? "Unknown Author")
                        .font(theme.labelFont(size: 15))
                        .foregroundStyle(theme.dayTextPrimary)

                    Text("\(estimatedReadTime) min read · \(theme.dayTitle)")
                        .font(theme.captionFont(size: 13))
                        .foregroundStyle(theme.dayTextSecondary)
                }
            }

            Rectangle()
                .fill(theme.dayDivider)
                .frame(height: 1)
        }
    }

    // MARK: - Block View

    @ViewBuilder
    private func dayBlockView(_ block: ContentBlock, contentWidth: CGFloat) -> some View {
        switch block {
        case .text(let content):
            Text(content)
                .font(.custom(theme.bodyFontName, size: fontSize))
                .foregroundStyle(theme.dayTextPrimary)
                .lineSpacing(fontSize * 0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, fontSize * 0.6)

        case .richText(let attrString):
            let _ = 0
            RichDayTextView(attributedText: attrString, fontSize: fontSize,
                           bodyFontName: theme.bodyFontName,
                           textColor: UIColor(theme.dayTextPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, fontSize * 0.6)

        case .heading(let content):
            Text(content)
                .font(theme.headlineFont(size: fontSize * 1.3))
                .foregroundStyle(theme.dayTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 8)

        case .snapshot(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var estimatedReadTime: Int {
        let totalPages = document?.pageCount ?? 1
        return max(1, totalPages * 2)
    }

    private func romanNumeral(_ n: Int) -> String {
        let values = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),
                      (100,"C"),(90,"XC"),(50,"L"),(40,"XL"),
                      (10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var result = ""
        var remaining = n
        for (value, numeral) in values {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }
}

// MARK: - Rich text view for Day Mode

private struct RichDayTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let fontSize: CGFloat
    let bodyFontName: String
    let textColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.foregroundColor, value: textColor, range: range)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.4
        mutable.addAttribute(.paragraphStyle, value: style, range: range)

        tv.attributedText = mutable
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
