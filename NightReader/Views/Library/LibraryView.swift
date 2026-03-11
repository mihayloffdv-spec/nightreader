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
                // Layered background: starry art faded at top, solid dark below
                libraryBackground

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
                        Image(systemName: "plus")
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
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.largeTitleTextAttributes = [
                    .foregroundColor: UIColor(NightTheme.accent),
                    .font: UIFont(name: "Georgia-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
                ]
                appearance.titleTextAttributes = [
                    .foregroundColor: UIColor(NightTheme.accent)
                ]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance

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

    // MARK: - Background: faded splash art at top + scattered stars + gradient to dark

    private var libraryBackground: some View {
        ZStack {
            NightTheme.background
                .ignoresSafeArea()

            // Faded splash art peeking at the top — very subtle
            VStack {
                Image("SplashArt")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 350)
                    .clipped()
                    .opacity(0.12)
                    .blur(radius: 8)
                    .overlay(
                        LinearGradient(
                            colors: [
                                NightTheme.background.opacity(0),
                                NightTheme.background.opacity(0.6),
                                NightTheme.background
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Spacer()
            }
            .ignoresSafeArea()

            // Scattered subtle stars across the background
            StarFieldView()
                .ignoresSafeArea()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Image(systemName: "book.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(NightTheme.accentSoft.opacity(0.4))

                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: CGFloat([5, 7, 4, 6, 3][i])))
                        .foregroundStyle(NightTheme.accent.opacity(Double([0.7, 0.5, 0.8, 0.4, 0.6][i])))
                        .offset(
                            x: CGFloat([-12, 8, -4, 14, 0][i]),
                            y: CGFloat([-40, -52, -62, -46, -72][i])
                        )
                }
            }

            Text("Your shelf is empty")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(NightTheme.secondaryText)

            Button {
                viewModel.showImporter = true
            } label: {
                Text("Import PDF")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NightTheme.accent)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .stroke(NightTheme.accent.opacity(0.5), lineWidth: 1)
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
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(books) { book in
                    BookCard(book: book) {
                        selectedBook = book
                    } onDelete: {
                        bookToDelete = book
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Scattered star field (subtle, ambient)

struct StarFieldView: View {
    // Pre-computed star positions for consistency
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = {
        var result: [(CGFloat, CGFloat, CGFloat, Double)] = []
        // Use a simple deterministic "random" based on index
        for i in 0..<30 {
            let seed = Double(i)
            let x = CGFloat((seed * 137.5).truncatingRemainder(dividingBy: 1.0) * 1.0)
            let y = CGFloat((seed * 251.3).truncatingRemainder(dividingBy: 1.0) * 1.0)
            let xNorm = CGFloat(abs(sin(seed * 3.14 * 0.37)))
            let yNorm = CGFloat(abs(cos(seed * 2.71 * 0.43)))
            let size = CGFloat(1.0 + abs(sin(seed * 1.7)) * 2.0)
            let opacity = 0.08 + abs(sin(seed * 2.3)) * 0.15
            result.append((xNorm, yNorm, size, opacity))
        }
        return result
    }()

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<stars.count, id: \.self) { i in
                let star = stars[i]
                Circle()
                    .fill(NightTheme.accentSoft)
                    .frame(width: star.size, height: star.size)
                    .opacity(star.opacity)
                    .position(
                        x: star.x * geo.size.width,
                        y: star.y * geo.size.height
                    )
            }
        }
    }
}

// MARK: - Book Card

struct BookCard: View {
    let book: Book
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                BookThumbnail(book: book)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(NightTheme.accentBlue.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: NightTheme.accentBlue.opacity(0.15), radius: 8, y: 4)

                Text(book.title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(NightTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let author = book.author {
                    Text(author)
                        .font(.system(size: 11))
                        .foregroundStyle(NightTheme.secondaryText)
                        .lineLimit(1)
                }

                if book.readProgress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(NightTheme.progressTrack)
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(NightTheme.progressFill)
                                .frame(width: geo.size.width * book.readProgress, height: 3)
                        }
                    }
                    .frame(height: 3)
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

// MARK: - Book thumbnail from first PDF page

struct BookThumbnail: View {
    let book: Book
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(NightTheme.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NightTheme.cardBackground)
            }
        }
        .task {
            image = await generateThumbnail(for: book)
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
