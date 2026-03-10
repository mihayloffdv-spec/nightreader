import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    @State private var viewModel = LibraryViewModel()
    @State private var selectedBook: Book?

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("NightReader")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showImporter = true
                    } label: {
                        Image(systemName: "plus")
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Books", systemImage: "book.closed")
        } description: {
            Text("Tap + to import a PDF")
        } actions: {
            Button("Import PDF") {
                viewModel.showImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var bookList: some View {
        List {
            ForEach(books) { book in
                Button {
                    selectedBook = book
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.headline)
                                .lineLimit(2)

                            if let author = book.author {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("\(book.totalPages) pages")
                                if book.readProgress > 0 {
                                    Text("·")
                                    Text("\(Int(book.readProgress * 100))%")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteBook(book, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
