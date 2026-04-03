import SwiftUI
import SwiftData
import PDFKit

// MARK: - Library View (Deep Forest design)
//
// Hero card with current book at top, grid of collection below, quote at bottom.
// Matches the "Private Collection" mockup.

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?

    private var theme: Theme { AppSettings.shared.currentTheme }
    private var currentBook: Book? { books.first }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if books.isEmpty {
                            emptyState
                        } else {
                            // Hero: current book
                            if let book = currentBook {
                                heroCard(book: book)
                            }

                            // Collection grid
                            collectionSection

                            // Bottom quote
                            quoteView
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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
                updateNavBarAppearance()
            }
        }
    }

    // MARK: - Hero Card

    private func heroCard(book: Book) -> some View {
        Button {
            openBook(book)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image — full width
                BookThumbnail(book: book, theme: theme)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        // Gradient overlay at bottom for text readability
                        LinearGradient(
                            colors: [.clear, theme.background.opacity(0.9)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(theme.headlineFont(size: 24))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(2)

                            if let author = book.author, !author.isEmpty {
                                Text(author)
                                    .font(theme.bodyFont(size: 14))
                                    .italic()
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .padding(16)
                    }

                // Progress bar
                if book.readProgress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.surface.opacity(0.3))
                                .frame(height: 3)

                            Rectangle()
                                .fill(theme.accent)
                                .frame(width: geo.size.width * book.readProgress, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Collection Grid

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(theme.libraryTitle)
                .font(theme.headlineFont(size: 20))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 20
            ) {
                // Skip the first book (shown as hero) if more than 1
                ForEach(books.count > 1 ? Array(books.dropFirst()) : books) { book in
                    BookCard(book: book, theme: theme) {
                        openBook(book)
                    } onDelete: {
                        bookToDelete = book
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Quote

    private var quoteView: some View {
        Text("\u{201C}Reading is a conversation. All books talk. But a good book listens as well.\u{201D}")
            .font(theme.bodyFont(size: 13))
            .italic()
            .foregroundStyle(theme.textSecondary.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 80)

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
                Label("Add PDF", systemImage: "plus")
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func openBook(_ book: Book) {
        if FileManager.default.fileExists(atPath: book.fileURL.path) {
            selectedBook = book
        } else {
            viewModel.errorMessage = "PDF file not found. It may have been deleted."
        }
    }

    private func updateNavBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [
            .foregroundColor: theme.accentUIColor,
            .font: theme.headlineUIFont(size: 34)
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: theme.accentUIColor
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Book Card

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
