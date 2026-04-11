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
    // Character-offset anchoring for EPUB/FB2 highlights (nil for PDF)
    var charOffset: Int?          // UTF-16 code unit offset in plainText(forPage:) output
    var charLength: Int?          // length in UTF-16 code units
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
        action: String? = nil,
        charOffset: Int? = nil,
        charLength: Int? = nil
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
        self.charOffset = charOffset
        self.charLength = charLength
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Book Annotations (aggregate)

struct BookAnnotations: Codable {
    /// Bump when adding new fields that need migration.
    /// v1 = highlights only, v2 = + smart highlights + chapter reviews + post-reading
    static let currentSchemaVersion = 2

    let id: String                // bookId
    let title: String
    let author: String?
    var schemaVersion: Int
    var highlights: [BookHighlight]
    var smartHighlights: [SmartHighlight]
    var chapterReviews: [ChapterReview]
    var postReading: PostReadingReview?
    var analysisCount: Int        // monthly counter for Settings display
    var highlightStats: SmartHighlightStats  // save/dismiss tracking for prompt tuning
    var argumentMaps: [ArgumentMap]

    init(id: String, title: String, author: String? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.schemaVersion = Self.currentSchemaVersion
        self.highlights = []
        self.smartHighlights = []
        self.chapterReviews = []
        self.postReading = nil
        self.analysisCount = 0
        self.highlightStats = SmartHighlightStats()
        self.argumentMaps = []
    }

    // Backward compat: old JSON files may not have all fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        highlights = try container.decodeIfPresent([BookHighlight].self, forKey: .highlights) ?? []
        smartHighlights = try container.decodeIfPresent([SmartHighlight].self, forKey: .smartHighlights) ?? []
        chapterReviews = try container.decodeIfPresent([ChapterReview].self, forKey: .chapterReviews) ?? []
        postReading = try container.decodeIfPresent(PostReadingReview.self, forKey: .postReading)
        analysisCount = try container.decodeIfPresent(Int.self, forKey: .analysisCount) ?? 0
        highlightStats = try container.decodeIfPresent(SmartHighlightStats.self, forKey: .highlightStats) ?? SmartHighlightStats()
        argumentMaps = try container.decodeIfPresent([ArgumentMap].self, forKey: .argumentMaps) ?? []
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
    let chapterIndex: Int         // sequential index (may change on reindex)
    let chapterTitle: String?     // display only
    let chapterHash: String?      // stable identity (hash of first 200 chars)
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
        chapterHash: String? = nil,
        text: String,
        type: SmartHighlightType,
        rationale: String,
        page: Int
    ) {
        self.id = UUID()
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.chapterHash = chapterHash
        self.text = text
        self.type = type
        self.rationale = rationale
        self.page = page
        self.dismissed = false
        self.savedAsHighlight = false
        self.createdAt = Date()
    }
}

// MARK: - Chapter Review (AI-powered reflection after each chapter)

struct ChapterReview: Identifiable, Codable {
    let id: UUID
    let chapterIndex: Int
    let chapterTitle: String?
    let questions: [String]       // AI-generated questions
    var answers: [String]         // user's answers (parallel to questions)
    var aiFeedback: [String]      // AI feedback per answer
    var summary: String?          // AI chapter summary
    let createdAt: Date

    init(chapterIndex: Int, chapterTitle: String?, questions: [String]) {
        self.id = UUID()
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.questions = questions
        self.answers = Array(repeating: "", count: questions.count)
        self.aiFeedback = []
        self.summary = nil
        self.createdAt = Date()
    }
}

// MARK: - Smart Highlight Stats (for AI prompt tuning)
//
// Tracks save/dismiss rates by type to tune future analysis prompts.
// Higher save rate → request more of that type. Higher dismiss rate → fewer.

struct SmartHighlightStats: Codable {
    var thesisSaved: Int = 0
    var thesisDismissed: Int = 0
    var insightSaved: Int = 0
    var insightDismissed: Int = 0
    var actionableSaved: Int = 0
    var actionableDismissed: Int = 0

    mutating func recordSave(type: SmartHighlightType) {
        switch type {
        case .thesis: thesisSaved += 1
        case .insight: insightSaved += 1
        case .actionable: actionableSaved += 1
        }
    }

    mutating func recordDismiss(type: SmartHighlightType) {
        switch type {
        case .thesis: thesisDismissed += 1
        case .insight: insightDismissed += 1
        case .actionable: actionableDismissed += 1
        }
    }

    /// Compute type weights (0.0-1.0) based on save rates.
    /// Types with higher save rates get higher weights.
    /// Returns nil if not enough data (< 5 total actions).
    func typeWeights() -> [SmartHighlightType: Double]? {
        let total = thesisSaved + thesisDismissed + insightSaved + insightDismissed + actionableSaved + actionableDismissed
        guard total >= 5 else { return nil }

        func saveRate(saved: Int, dismissed: Int) -> Double {
            let actions = saved + dismissed
            guard actions > 0 else { return 0.5 } // no data → neutral
            return Double(saved) / Double(actions)
        }

        let rates: [SmartHighlightType: Double] = [
            .thesis: saveRate(saved: thesisSaved, dismissed: thesisDismissed),
            .insight: saveRate(saved: insightSaved, dismissed: insightDismissed),
            .actionable: saveRate(saved: actionableSaved, dismissed: actionableDismissed)
        ]

        // Normalize so they sum to ~1.0 (proportional weighting)
        let sum = rates.values.reduce(0, +)
        guard sum > 0 else { return nil }
        return rates.mapValues { $0 / sum }
    }
}

// MARK: - Post-Reading Review

struct PostReadingReview: Codable {
    var coreIdea: String?         // main idea in own words
    var whyRead: String?          // why you read this
    var mainShift: String?        // what changed in your thinking
    var completedAt: Date?
}
