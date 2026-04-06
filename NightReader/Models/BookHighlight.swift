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
    var smartHighlights: [SmartHighlight]
    var postReading: PostReadingReview?
    var analysisCount: Int        // monthly counter for Settings display

    init(id: String, title: String, author: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.highlights = []
        self.smartHighlights = []
        self.postReading = nil
        self.analysisCount = 0
    }
}

// MARK: - Smart Highlight (AI-generated)
//
// AI analyzes chapter text and marks valuable sentences.
// Separate from BookHighlight: different lifecycle, metadata, and UI.
//
//  AI analysis → SmartHighlight[] → Notebook "✦ AI" tab
//                                    ├── Save → promotes to BookHighlight
//                                    └── Dismiss → gone forever

enum SmartHighlightType: String, Codable {
    case thesis      // ✦ Core argument or claim
    case insight     // 💡 Non-obvious observation
    case actionable  // ⚡ Something reader can apply
}

struct SmartHighlight: Identifiable, Codable {
    let id: UUID
    let bookId: String
    let chapterIndex: Int         // stable key (not title)
    let chapterTitle: String?     // display only
    let text: String              // exact sentence from book
    let type: SmartHighlightType
    let rationale: String         // AI's book-aware explanation
    let page: Int                 // page where found (for navigation)
    var dismissed: Bool
    var savedAsHighlight: Bool    // promoted to BookHighlight
    let createdAt: Date

    init(
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String? = nil,
        text: String,
        type: SmartHighlightType,
        rationale: String,
        page: Int
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.text = text
        self.type = type
        self.rationale = rationale
        self.page = page
        self.dismissed = false
        self.savedAsHighlight = false
        self.createdAt = Date()
    }
}

// MARK: - Post-Reading Review

struct PostReadingReview: Codable {
    var coreIdea: String?         // main idea in own words
    var whyRead: String?          // why you read this
    var mainShift: String?        // what changed in your thinking
    var completedAt: Date?
}
