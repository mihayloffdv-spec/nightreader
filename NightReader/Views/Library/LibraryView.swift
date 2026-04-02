import SwiftUI
import SwiftData
import PDFKit

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?

    var body: some View {
        NavigationStack {
            ZStack {
                NightTheme.background
                    .ignoresSafeArea()

                Group {
                    if books.isEmpty {
                        emptyState
                    } else {
                        bookGrid
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(NightTheme.accent)
                    }
                }
            }
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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-autoOpenFirst") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let first = books.first {
                            selectedBook = first
                        }
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(NightTheme.tertiaryText)

            Text("Your library is empty")
                .font(.title3.weight(.regular))
                .foregroundStyle(NightTheme.secondaryText)

            Button {
                viewModel.showImporter = true
            } label: {
                Label("Add PDF", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(NightTheme.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .stroke(NightTheme.accent.opacity(0.4), lineWidth: 1)
                    )
            }

            Spacer()
        }
    }

    // MARK: - Book Grid

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ],
                spacing: 24
            ) {
                ForEach(books) { book in
                    BookCard(book: book) {
                        if FileManager.default.fileExists(atPath: book.fileURL.path) {
                            selectedBook = book
                        } else {
                            viewModel.errorMessage = "PDF file not found. It may have been deleted."
                        }
                    } onDelete: {
                        bookToDelete = book
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Book Card

struct BookCard: View {
    let book: Book
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Cover
                BookThumbnail(book: book)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

                // Title + author + reading time
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(NightTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(NightTheme.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        // Progress
                        if book.readProgress > 0 {
                            Text("\(Int(book.readProgress * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(NightTheme.tertiaryText)
                        }

                        // Reading time
                        if let readingTime = book.formattedReadingTime {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(readingTime)
                                    .font(.caption2)
                            }
                            .foregroundStyle(NightTheme.tertiaryText)
                        }
                    }
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
                    .fill(NightTheme.cardBackground)
                    .overlay {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundStyle(NightTheme.tertiaryText)
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
