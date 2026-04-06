import Foundation

// MARK: - Book Highlight
//
// A single text highlight with optional reaction and action.
// Stored in JSON via AnnotationStore.

struct BookHighlight: Identifiable, Codable {
    let id: UUID
    let bookId: String
    let text: String              // highlighted text
    let page: Int                 // page index (0-based)
    let bounds: [[CGFloat]]       // [[x, y, w, h], ...] per line rect
    let chapter: String?          // chapter name (if detected)
    let color: String             // "yellow", "green", "blue", "pink", "orange"
    var reaction: String?         // 🎭 why it resonated
    var action: String?           // ⚡ what to do about it
    var committed: Bool           // marked as "will actually do" in post-reading
    let createdAt: Date
    var updatedAt: Date

    init(
        bookId: String,
        text: String,
        page: Int,
        bounds: [[CGFloat]] = [],
        chapter: String? = nil,
        color: String = "yellow",
        reaction: String? = nil,
        action: String? = nil
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.text = text
        self.page = page
        self.bounds = bounds
        self.chapter = chapter
        self.color = color
        self.reaction = reaction
        self.action = action
        self.committed = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Book Annotations (aggregate)

struct BookAnnotations: Codable {
    let id: String                // bookId
    let title: String
    let author: String?
    var highlights: [BookHighlight]
    var postReading: PostReadingReview?

    init(id: String, title: String, author: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.highlights = []
        self.postReading = nil
    }
}

// MARK: - Post-Reading Review

struct PostReadingReview: Codable {
    var coreIdea: String?         // main idea in own words
    var whyRead: String?          // why you read this
    var mainShift: String?        // what changed in your thinking
    var completedAt: Date?
}
