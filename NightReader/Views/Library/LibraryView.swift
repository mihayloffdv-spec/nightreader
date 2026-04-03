import SwiftUI
import SwiftData
import PDFKit

// MARK: - Library View (Deep Forest — exact mockup replica)
//
// ┌─────────────────────────────────────┐
// │  ≡  NightReader                  ⚙  │
// │                                     │
// │  Currently Reading     WINTER 2024  │
// │                                     │
// │  ┌─────────────────────────────┐   │
// │  │      [book cover]           │   │
// │  └─────────────────────────────┘   │
// │                                     │
// │  Book Title                         │
// │  by Author Name                     │
// │                                     │
// │  124 OF 310 PAGES   40% COMPLETE    │
// │  ══════════════                     │
// │                                     │
// │  [ ▶ Resume Journey ] [ Notes ]     │
// │                                     │
// │  Private Collection                 │
// │  ┌────┐ ┌────┐                     │
// │  │    │ │    │                     │
// │  └────┘ └────┘                     │
// │                                     │
// │  "Reading is a conversation..."     │
// └─────────────────────────────────────┘

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?

    private var theme: Theme { AppSettings.shared.currentTheme }
    private var currentBook: Book? { books.first }
    private var otherBooks: [Book] { books.count > 1 ? Array(books.dropFirst()) : [] }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                if books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Top bar: hamburger + NightReader + gear
                            topBar
                                .padding(.horizontal, 24)
                                .padding(.top, 8)

                            // Currently Reading section
                            if let book = currentBook {
                                currentlyReadingSection(book: book)
                            }

                            // Private Collection grid (other books)
                            if !otherBooks.isEmpty {
                                collectionSection
                            }

                            // Bottom quote
                            quoteView
                                .padding(.top, 24)
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.importPDF(from: url, context: modelContext)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
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
            .confirmationDialog(
                "Delete this book?",
                isPresented: .init(
                    get: { bookToDelete != nil },
                    set: { if !$0 { bookToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        viewModel.deleteBook(book, context: modelContext)
                    }
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) { bookToDelete = nil }
            } message: {
                Text("This will remove the book and all its highlights.")
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderView(book: book)
            }
            .onAppear {
                PDFImportService.scanForUntrackedPDFs(context: modelContext)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(theme.textSecondary)

            Text("NightReader")
                .font(theme.headlineFont(size: 20))
                .foregroundStyle(theme.accent)

            Spacer()

            Button {
                viewModel.showImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    // MARK: - Currently Reading

    private func currentlyReadingSection(book: Book) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(alignment: .top) {
                Text("Currently\nReading")
                    .font(theme.headlineFont(size: 26))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                VStack(alignment: .trailing) {
                    let dateFormatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "MMMM\nyyyy"
                        return f
                    }()
                    Text(dateFormatter.string(from: Date()).uppercased())
                        .font(theme.captionFont(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .kerning(1)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Book card with cover
            Button { openBook(book) } label: {
                VStack(spacing: 0) {
                    // Cover in bordered card
                    BookThumbnail(book: book, theme: theme)
                        .frame(height: 300)
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(theme.surface.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 24)

            // Book info below card
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(book.title)
                    .font(theme.headlineFont(size: 28))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(3)

                // Author
                if let author = book.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(theme.bodyFont(size: 15))
                        .italic()
                        .foregroundStyle(theme.textSecondary)
                }

                // Page count + progress
                HStack(spacing: 16) {
                    let currentPage = book.lastPageIndex + 1
                    let totalPages = max(book.totalPages, 1)
                    let percent = Int(book.readProgress * 100)

                    Text("\(currentPage) OF \(totalPages) PAGES")
                        .font(theme.captionFont(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .kerning(1.5)

                    Text("\(percent)% COMPLETE")
                        .font(theme.captionFont(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .kerning(1.5)
                }
                .padding(.top, 4)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.surface.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.accent)
                            .frame(width: geo.size.width * max(book.readProgress, 0.02), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.top, 8)

                // Action buttons
                HStack(spacing: 12) {
                    // Resume Journey
                    Button { openBook(book) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("Resume\nJourney")
                                .font(theme.labelFont(size: 14))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(theme.background)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(theme.accent)
                        )
                    }

                    // Notes button
                    Button { } label: {
                        Text("Notes")
                            .font(theme.labelFont(size: 14))
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .stroke(theme.surface.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - Private Collection

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(theme.libraryTitle)
                .font(theme.headlineFont(size: 20))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 32)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(otherBooks) { book in
                    BookCard(book: book, theme: theme) {
                        openBook(book)
                    } onDelete: {
                        bookToDelete = book
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Quote

    private var quoteView: some View {
        Text("\u{201C}Reading is a conversation. All books talk. But a good book listens as well.\u{201D}")
            .font(theme.bodyFont(size: 13))
            .italic()
            .foregroundStyle(theme.textSecondary.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            // Top bar even in empty state
            topBar
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(theme.surface)

            VStack(spacing: 8) {
                Text("Your library is empty")
                    .font(theme.headlineFont(size: 22))
                    .foregroundStyle(theme.textPrimary)

                Text("Add a PDF to begin your reading journey")
                    .font(theme.captionFont(size: 15))
                    .foregroundStyle(theme.textSecondary)
            }

            Button {
                viewModel.showImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add PDF")
                }
                .font(theme.labelFont(size: 16))
                .foregroundStyle(theme.background)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(theme.accent)
                )
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func openBook(_ book: Book) {
        if FileManager.default.fileExists(atPath: book.fileURL.path) {
            selectedBook = book
        } else {
            viewModel.errorMessage = "PDF file not found. It may have been deleted."
        }
    }
}

// MARK: - Book Card (grid item)

struct BookCard: View {
    let book: Book
    let theme: Theme
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                BookThumbnail(book: book, theme: theme)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                Text(book.title)
                    .font(theme.labelFont(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(theme.captionFont(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                if book.readProgress > 0 {
                    Text("\(Int(book.readProgress * 100))%")
                        .font(theme.captionFont(size: 11).monospacedDigit())
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
                    .fill(theme.backgroundElevated)
                    .overlay {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundStyle(theme.surface)
                    }
            }
        }
        .task {
            let key = book.id.uuidString as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
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
