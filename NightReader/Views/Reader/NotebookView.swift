import SwiftUI
import PDFKit

// MARK: - Notebook View (Deep Forest design)
//
// Full-screen view of all highlights for a book.
// Pill filters, highlight cards with reactions/actions, bottom quote.
//
// ┌─────────────────────────────────────────┐
// │  NightReader                        ↗   │
// │  CURRENT READING                        │
// │  The Hidden Life of Trees               │
// │  Peter Wohlleben · 42%                  │
// │                                         │
// │  [ALL] [REACTIONS] [ACTIONS]            │
// │                                         │
// │  "A tree can be only as strong as..."   │
// │  🎭 This resonates deeply...            │
// │  ⚡ Research urban forestry...           │
// │                                         │
// │  "They are very slow. Their heartbeat   │
// │   is measured in years."                │
// │  🎭 Beautiful metaphor                  │
// │                                         │
// │  "Reading is a conversation..."         │
// └─────────────────────────────────────────┘

struct NotebookView: View {
    let document: PDFDocument?
    let bookTitle: String
    let bookAuthor: String?
    let readProgress: Double
    let theme: Theme
    let onSelectAnnotation: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [AnnotationInfo] = []
    @State private var selectedFilter: NotebookFilter = .all

    enum NotebookFilter: String, CaseIterable {
        case all = "All"
        case reactions = "Reactions"
        case actions = "Actions"
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Filters
                filterPills
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Content
                if filteredAnnotations.isEmpty {
                    emptyState
                } else {
                    highlightList
                }
            }
        }
        .onAppear { loadAnnotations() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NightReader")
                    .font(theme.labelFont(size: 14))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Text("CURRENT READING")
                .font(theme.captionFont(size: 10))
                .foregroundStyle(theme.textSecondary)
                .kerning(2)

            Text(bookTitle)
                .font(theme.headlineFont(size: 26))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 8) {
                if let author = bookAuthor, !author.isEmpty {
                    Text(author)
                        .font(theme.bodyFont(size: 14))
                        .italic()
                        .foregroundStyle(theme.textSecondary)
                }

                if readProgress > 0 {
                    Text("· \(Int(readProgress * 100))%")
                        .font(theme.captionFont(size: 14))
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    // MARK: - Filters

    private var filterPills: some View {
        HStack(spacing: 10) {
            ForEach(NotebookFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue.uppercased())
                        .font(theme.captionFont(size: 11))
                        .kerning(1)
                        .foregroundStyle(selectedFilter == filter ? theme.background : theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? theme.accent : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? Color.clear : theme.surface.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            Spacer()
        }
    }

    // MARK: - Highlight List

    private var highlightList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(filteredAnnotations) { info in
                    highlightCard(info)
                        .onTapGesture {
                            dismiss()
                            onSelectAnnotation(info.pageIndex)
                        }
                }

                // Bottom quote
                Text("\u{201C}They are very slow. Their heartbeat is measured in years.\u{201D}")
                    .font(theme.bodyFont(size: 14))
                    .italic()
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - Highlight Card

    private func highlightCard(_ info: AnnotationInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Quoted text
            HStack(alignment: .top, spacing: 12) {
                // Accent dot
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                Text("\u{201C}\(info.text)\u{201D}")
                    .font(theme.bodyFont(size: 15))
                    .italic()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(4)
            }

            // Note/reaction if exists
            if let note = info.note, !note.isEmpty {
                Text(note)
                    .font(theme.captionFont(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.leading, 20)
            }

            // Page reference
            Text("p. \(info.pageIndex + 1)")
                .font(theme.captionFont(size: 11))
                .foregroundStyle(theme.textSecondary.opacity(0.6))
                .padding(.leading, 20)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.backgroundElevated)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bookmark")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(theme.surface)

            Text("No highlights yet")
                .font(theme.headlineFont(size: 18))
                .foregroundStyle(theme.textPrimary)

            Text("Select text in the reader and tap Highlight")
                .font(theme.captionFont(size: 14))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Data

    private var filteredAnnotations: [AnnotationInfo] {
        switch selectedFilter {
        case .all:
            return annotations
        case .reactions:
            return annotations.filter { $0.note != nil && !($0.note?.isEmpty ?? true) }
        case .actions:
            // For now, no separate action field — filter by note containing ⚡
            return annotations.filter { $0.note?.contains("⚡") ?? false }
        }
    }

    private func loadAnnotations() {
        guard let document else { return }
        annotations = AnnotationService.allHighlights(in: document)
    }
}
