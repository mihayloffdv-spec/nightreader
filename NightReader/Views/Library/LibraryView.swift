import SwiftUI
import SwiftData
import PDFKit

// MARK: - Library View (pixel-perfect from HTML mockup)
//
// Translated 1:1 from Stitch HTML source. Every color hex, font size,
// padding, border radius, gradient, and shadow matches the CSS.

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?
    @State private var bookToRename: Book?
    @State private var renameText: String = ""

    private var theme: Theme { AppSettings.shared.currentTheme }

    // Theme-derived colors (mapped from former hardcoded Deep Forest values)
    private var bg: Color { theme.background }
    private var surface: Color { theme.surfaceLowest }
    private var surfaceContainerLow: Color { theme.surfaceContainerLow }
    private var surfaceContainer: Color { theme.surfaceContainer }
    private var surfaceContainerHigh: Color { theme.surfaceContainerHigh }
    private var surfaceContainerHighest: Color { theme.surfaceContainerHighest }
    private var onSurface: Color { theme.onSurface }
    private var primary: Color { theme.primary }
    private var onPrimary: Color { theme.onPrimary }
    private var accent: Color { theme.accent }
    private var accentDark: Color { theme.accentMuted }
    private var secondary: Color { theme.surfaceLight }
    private var stone400: Color { theme.textSecondary.opacity(0.7) }
    private var stone500: Color { theme.textSecondary.opacity(0.5) }
    private var stone600: Color { theme.textSecondary.opacity(0.35) }
    private var outlineVariant: Color { theme.outlineVariant }

    private var currentBook: Book? { books.first }
    private var otherBooks: [Book] { books.count > 1 ? Array(books.dropFirst()) : [] }

    var body: some View {
        NavigationStack {
            ZStack {
                surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if books.isEmpty {
                            emptyState
                        } else {
                            heroSection
                            gridSection
                            statsSection
                        }
                    }
                    .padding(.top, 80) // below fixed header
                    .padding(.bottom, 32)
                }

                // Fixed header
                VStack {
                    header
                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.importPDF(from: url, context: modelContext)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog("Delete this book?", isPresented: .init(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let b = bookToDelete { viewModel.deleteBook(b, context: modelContext) }
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) { bookToDelete = nil }
            } message: {
                Text("This will remove the book and all its highlights.")
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderView(book: book)
            }
            .alert("Rename Book", isPresented: .init(
                get: { bookToRename != nil },
                set: { if !$0 { bookToRename = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Save") {
                    if let b = bookToRename {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            b.title = trimmed
                            try? modelContext.save()
                        }
                    }
                    bookToRename = nil
                }
                Button("Cancel", role: .cancel) { bookToRename = nil }
            }
            .onAppear {
                PDFImportService.scanForUntrackedPDFs(context: modelContext)
                cleanupMessyTitles()
            }
        }
    }

    /// One-time migration: re-clean titles that look like raw filenames.
    private func cleanupMessyTitles() {
        for book in books {
            // If title still has underscores or a trailing numeric ID, clean it
            if book.title.contains("_") || looksLikeRawFilename(book.title) {
                book.title = PDFImportService.cleanFilename(book.title)
            }
        }
        try? modelContext.save()
    }

    private func looksLikeRawFilename(_ s: String) -> Bool {
        // Contains a 5+ digit run at the end, after a space or underscore
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "_" })
        guard let last = parts.last, last.count >= 5 else { return false }
        return last.allSatisfy { $0.isNumber }
    }

    private func startRename(_ book: Book) {
        renameText = book.title
        bookToRename = book
    }

    // MARK: - Header (fixed, bg-[#0B120B]/80 backdrop-blur-xl, h-16, px-6)

    private var header: some View {
        HStack {
            HStack(spacing: 16) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .foregroundStyle(stone400)

                Text("NightReader")
                    .font(.custom("Onest", size: 24).bold())
                    .tracking(-0.8) // tracking-tighter
                    .foregroundStyle(accent)
            }

            Spacer()

            Image(systemName: "gearshape")
                .font(.system(size: 20))
                .foregroundStyle(stone400)
        }
        .padding(.horizontal, 24) // px-6
        .frame(height: 64) // h-16
        .background(bg.opacity(0.8))
        .background(.ultraThinMaterial)
    }

    // MARK: - Hero Section (Currently Reading)

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header: "Currently Reading" + "Winter 2024"
            HStack(alignment: .bottom) {
                Text("Currently Reading")
                    .font(.custom("Onest", size: 30).bold())
                    .tracking(-0.4) // tracking-tight
                    .foregroundStyle(onSurface)

                Spacer()

                Text(currentSeasonYear)
                    .font(.custom("Onest", size: 14))
                    .textCase(.uppercase)
                    .tracking(4) // tracking-widest
                    .foregroundStyle(primary.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32) // mb-8

            // Hero card
            if let book = currentBook {
                heroCard(book: book)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 64) // mb-16
    }

    private func heroCard(book: Book) -> some View {
        // bg-surface-container-low, p-8, rounded-xl, border primary/10, custom-glow
        VStack(spacing: 0) {
            // Cover image centered
            Button { openBook(book) } label: {
                BookThumbnail(book: book, theme: AppSettings.shared.currentTheme)
                    .frame(width: 192, height: 288) // w-48, aspect-[2/3]
                    .clipShape(RoundedRectangle(cornerRadius: 2)) // rounded-sm
                    .shadow(color: .black.opacity(0.7), radius: 30, x: 10, y: 10)
                    // ring-1 ring-white/10
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // Book info
            VStack(alignment: .leading, spacing: 24) {
                // Title + author
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.custom("Onest", size: 36).weight(.heavy))
                        .tracking(-0.8) // tracking-tighter
                        .foregroundStyle(onSurface)
                        .lineLimit(3)

                    if let author = book.author, !author.isEmpty {
                        Text("by \(author)")
                            .font(.custom("Noto Serif", size: 18))
                            .italic()
                            .foregroundStyle(secondary)
                    }
                }

                // Stats + progress
                VStack(spacing: 12) {
                    // Stats row
                    HStack {
                        let currentPage = book.lastPageIndex + 1
                        let totalPages = max(book.totalPages, 1)
                        let percent = Int(book.readProgress * 100)

                        Text("\(currentPage) of \(totalPages) pages")
                            .font(.custom("Onest", size: 12))
                            .textCase(.uppercase)
                            .tracking(4)
                            .foregroundStyle(stone500)

                        Spacer()

                        Text("\(percent)% Complete")
                            .font(.custom("Onest", size: 12))
                            .textCase(.uppercase)
                            .tracking(4)
                            .foregroundStyle(stone500)
                    }

                    // Progress bar: h-1, editorial-gradient, glow
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 9999)
                                .fill(surfaceContainerHighest)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 9999)
                                .fill(
                                    LinearGradient(
                                        colors: [primary, accentDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: geo.size.width * max(book.readProgress, 0.02), height: 4)
                                .shadow(color: primary.opacity(0.5), radius: 5)
                        }
                    }
                    .frame(height: 4)
                }

                // Resume Journey
                Button { openBook(book) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text("Resume Journey")
                            .font(.custom("Onest", size: 15).bold())
                    }
                    .foregroundStyle(onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [primary, accentDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: primary.opacity(0.2), radius: 12)
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(32) // p-8
        .background(
            RoundedRectangle(cornerRadius: 12) // rounded-xl
                .fill(surfaceContainerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.3), radius: 20, x: 0, y: 0) // custom-glow
        )
        .contextMenu {
            Button { startRename(book) } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { bookToDelete = book } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Grid Section (Your Conservatory)

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Conservatory")
                        .font(.custom("Onest", size: 24).bold())
                        .tracking(-0.4)
                        .foregroundStyle(onSurface)

                    Text("Curated volumes of natural wisdom")
                        .font(.custom("Noto Serif", size: 14))
                        .italic()
                        .foregroundStyle(stone500)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40) // mb-10

            // Book grid: 2 columns, gap-x-8 (32), gap-y-12 (48)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 32),
                    GridItem(.flexible(), spacing: 32)
                ],
                spacing: 48
            ) {
                ForEach(otherBooks) { book in
                    gridBookCard(book: book)
                }

                // Import card (dashed border)
                importCard
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 64) // mb-16
    }

    private func gridBookCard(book: Book) -> some View {
        Button { openBook(book) } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Cover: aspect-[3/4], rounded-lg, shadow-xl
                BookThumbnail(book: book, theme: AppSettings.shared.currentTheme)
                    .aspectRatio(3.0/4.0, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    .overlay(alignment: .topTrailing) {
                        if book.highlightCount > 0 {
                            Text("\(book.highlightCount)")
                                .font(.custom("Onest", size: 10).bold())
                                .foregroundStyle(onPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accent))
                                .padding(6)
                        }
                    }
                    .padding(.bottom, 16) // mb-4

                // Title: font-headline font-bold leading-tight
                Text(book.title)
                    .font(.custom("Onest", size: 15).bold())
                    .foregroundStyle(onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 4) // mb-1

                // Author: 10px uppercase tracking-widest stone-500
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.custom("Onest", size: 10))
                        .textCase(.uppercase)
                        .tracking(4)
                        .foregroundStyle(stone500)
                }
            }
        }
        .contextMenu {
            Button { startRename(book) } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { bookToDelete = book } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var importCard: some View {
        Button { viewModel.showImporter = true } label: {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(stone600)

                Text("Import Book")
                    .font(.custom("Onest", size: 10))
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(stone500)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(outlineVariant.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(RoundedRectangle(cornerRadius: 8).fill(surfaceContainerLow))
            )
        }
    }

    // MARK: - Stats Section (Bento)

    private var statsSection: some View {
        HStack(spacing: 24) {
            // Reading streak
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Reading Streak")
                        .font(.custom("Onest", size: 18).bold())
                        .foregroundStyle(onSurface)

                    Text("Keep the momentum going.")
                        .font(.custom("Noto Serif", size: 14))
                        .italic()
                        .foregroundStyle(stone400)
                }

                Spacer()

                Text("\(books.count)d")
                    .font(.custom("Onest", size: 40).weight(.heavy))
                    .tracking(-1.6)
                    .foregroundStyle(accent)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(surfaceContainerLow)
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 100)

            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(stone600)

            VStack(spacing: 8) {
                Text("Your library is empty")
                    .font(.custom("Onest", size: 24).bold())
                    .foregroundStyle(onSurface)

                Text("Import a PDF to begin your reading journey")
                    .font(.custom("Noto Serif", size: 15))
                    .italic()
                    .foregroundStyle(stone500)
            }

            Button { viewModel.showImporter = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Import Book")
                        .font(.custom("Onest", size: 15).bold())
                }
                .foregroundStyle(onPrimary)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [primary, accentDark],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private func openBook(_ book: Book) {
        if FileManager.default.fileExists(atPath: book.fileURL.path) {
            selectedBook = book
        } else {
            viewModel.errorMessage = "PDF file not found."
        }
    }

    private var currentSeasonYear: String {
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        let season: String
        switch month {
        case 3...5: season = "Spring"
        case 6...8: season = "Summer"
        case 9...11: season = "Autumn"
        default: season = "Winter"
        }
        return "\(season) \(year)"
    }
}

// MARK: - Book Thumbnail

struct BookThumbnail: View {
    let book: Book
    let theme: Theme
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(theme.surfaceContainer)
                    .overlay {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundStyle(theme.outlineVariant)
                    }
            }
        }
        .task {
            let key = book.id.uuidString as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached; return
            }
            if let generated = await generateThumbnail(for: book) {
                Self.cache.setObject(generated, forKey: key)
                image = generated
            }
        }
    }

    private func generateThumbnail(for book: Book) async -> UIImage? {
        await Task.detached {
            guard let doc = PDFDocument(url: book.fileURL),
                  let page = doc.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 300, height: 400), for: .cropBox)
        }.value
    }
}

// BookCard kept for compatibility but LibraryView uses gridBookCard directly
struct BookCard: View {
    let book: Book; let theme: Theme; var onTap: () -> Void; var onDelete: () -> Void
    var body: some View {
        Button(action: onTap) { Text(book.title) }
    }
}
