import SwiftUI
import PDFKit

// MARK: - Notebook View (pixel-perfect from HTML mockup)
//
// Journal-style highlight cards with iOS bottom-sheet aesthetic.
// Each card: drag indicator, page ref, blockquote, reaction box.

struct NotebookView: View {
    let document: PDFDocument?
    let bookTitle: String
    let bookAuthor: String?
    let readProgress: Double
    let theme: Theme
    let onSelectAnnotation: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [AnnotationInfo] = []
    @State private var selectedFilter: Int = 0

    // Exact colors from HTML
    private let surface = Color(hex: "#0e150e")
    private let surfaceLowest = Color(hex: "#091009")
    private let surfaceContainerLow = Color(hex: "#161d16")
    private let surfaceContainerHigh = Color(hex: "#242c24")
    private let surfaceContainerHighest = Color(hex: "#2f372e")
    private let onSurface = Color(hex: "#dde5d8")
    private let onSurfaceVariant = Color(hex: "#c5c7c1")
    private let primary = Color(hex: "#ffb599")
    private let onPrimary = Color(hex: "#5a1c00")
    private let accent = Color(hex: "#CC704B")
    private let accentDark = Color(hex: "#bd6440")
    private let outline = Color(hex: "#8e928b")
    private let outlineVariant = Color(hex: "#444843")
    private let stone400 = Color(hex: "#a8a29e")

    private let filters = ["All", "Reactions", "Actions"]

    var body: some View {
        ZStack {
            // journal-backdrop: gradient surface → surface-lowest
            LinearGradient(colors: [surface, surfaceLowest], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Editorial header
                    journalHeader
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40) // mb-10

                    // Filter tabs
                    filterTabs
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48) // mb-12

                    // Cards stack — space-y-8 = 32px
                    LazyVStack(spacing: 32) {
                        if filteredAnnotations.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredAnnotations) { info in
                                journalCard(info)
                                    .onTapGesture {
                                        dismiss()
                                        onSelectAnnotation(info.pageIndex)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .padding(.top, 16)
            }
        }
        .onAppear { loadAnnotations() }
    }

    // MARK: - Header

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: "CURRENT READING" + "24 Highlights"
            HStack(alignment: .bottom) {
                Text("Current Reading")
                    .font(.custom("Onest", size: 12).bold())
                    .textCase(.uppercase)
                    .tracking(2.4) // 0.2em
                    .foregroundStyle(primary)

                Spacer()

                Text("\(annotations.count) Highlights")
                    .font(.custom("Onest", size: 10))
                    .foregroundStyle(outline)
            }
            .padding(.bottom, 8) // mb-2

            // Title — 4xl extrabold tracking-tight leading-none
            Text(bookTitle)
                .font(.custom("Onest", size: 36).weight(.heavy))
                .tracking(-0.4)
                .foregroundStyle(onSurface)
                .lineLimit(3)
                .padding(.bottom, 16) // mb-4

            // Author — italic opacity-80
            if let author = bookAuthor, !author.isEmpty {
                Text(author)
                    .font(.custom("Noto Serif", size: 16))
                    .italic()
                    .foregroundStyle(onSurfaceVariant.opacity(0.8))
            }
        }
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 8) { // gap-2
            ForEach(Array(filters.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = index }
                } label: {
                    Text(title)
                        .font(.custom("Onest", size: 12).bold())
                        .textCase(.uppercase)
                        .tracking(4) // tracking-widest
                        .foregroundStyle(selectedFilter == index ? onPrimary : stone400)
                        .padding(.horizontal, 24) // px-6
                        .padding(.vertical, 8) // py-2
                        .background(
                            Capsule().fill(selectedFilter == index ? primary : surfaceContainerHigh)
                        )
                        .shadow(color: selectedFilter == index ? primary.opacity(0.1) : .clear, radius: 12)
                }
            }
            Spacer()
        }
    }

    // MARK: - Journal Card

    private func journalCard(_ info: AnnotationInfo) -> some View {
        // bg-surface-container-low rounded-t-[2.5rem] rounded-b-xl p-8 pt-10
        // shadow-2xl shadow-black/20, border-t outline-variant/10
        VStack(alignment: .leading, spacing: 0) {
            // Drag indicator — w-12 h-1 bg-outline-variant/30 centered
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 9999)
                    .fill(outlineVariant.opacity(0.3))
                    .frame(width: 48, height: 4)
                Spacer()
            }
            .padding(.bottom, 24) // space to content

            // Page ref + quote icon
            HStack {
                // "PAGE 42 • CH. 2" — 10px primary/60 bold tracking-tighter
                Text("PAGE \(info.pageIndex + 1)")
                    .font(.custom("Onest", size: 10).bold())
                    .tracking(-0.4)
                    .foregroundStyle(primary.opacity(0.6))

                Spacer()

                // Quote icon — filled, primary
                Image(systemName: "quote.opening")
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
            }
            .padding(.bottom, 24) // mb-6

            // Blockquote — text-2xl italic leading-relaxed
            Text("\u{201C}\(info.text)\u{201D}")
                .font(.custom("Noto Serif", size: 24))
                .italic()
                .foregroundStyle(onSurface)
                .lineSpacing(6) // leading-relaxed
                .padding(.bottom, 32) // mb-8

            // Reaction box (if note exists)
            if let note = info.note, !note.isEmpty {
                reactionBox(note: note)
            }
        }
        .padding(32) // p-8
        .padding(.top, 8) // pt-10 total (32+8=40)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 40, // rounded-t-[2.5rem]
                bottomLeadingRadius: 12, // rounded-b-xl
                bottomTrailingRadius: 12,
                topTrailingRadius: 40
            )
            .fill(surfaceContainerLow)
            .overlay(alignment: .top) {
                // border-t outline-variant/10
                Rectangle()
                    .fill(outlineVariant.opacity(0.1))
                    .frame(height: 1)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 4) // shadow-2xl
    }

    // MARK: - Reaction Box

    private func reactionBox(note: String) -> some View {
        // p-5 rounded-2xl bg-surface-container-highest/50 backdrop-blur-sm border outline-variant/5
        HStack(alignment: .top, spacing: 16) { // gap-4
            // Gradient dot — w-8 h-8 terracotta-glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [primary, accentDark],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 32, height: 32)

                Text("💭")
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                // "OBSERVATION" — 10px extrabold uppercase tracking-widest primary
                Text("Observation")
                    .font(.custom("Onest", size: 10).weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(primary)

                // Note text — body sm on-surface-variant leading-relaxed
                Text(note)
                    .font(.custom("Noto Serif", size: 14))
                    .foregroundStyle(onSurfaceVariant)
                    .lineSpacing(4)
            }
        }
        .padding(20) // p-5
        .background(
            RoundedRectangle(cornerRadius: 16) // rounded-2xl
                .fill(surfaceContainerHighest.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(outlineVariant.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "quote.opening")
                .font(.system(size: 40))
                .foregroundStyle(outlineVariant)

            Text("No highlights yet")
                .font(.custom("Onest", size: 20).bold())
                .foregroundStyle(onSurface)

            Text("Select text in the reader and tap Highlight")
                .font(.custom("Noto Serif", size: 14))
                .foregroundStyle(onSurfaceVariant)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private var filteredAnnotations: [AnnotationInfo] {
        switch selectedFilter {
        case 1: return annotations.filter { $0.note != nil && !($0.note?.isEmpty ?? true) }
        case 2: return annotations.filter { $0.note?.contains("⚡") ?? false }
        default: return annotations
        }
    }

    private func loadAnnotations() {
        guard let document else { return }
        annotations = AnnotationService.allHighlights(in: document)
    }
}
