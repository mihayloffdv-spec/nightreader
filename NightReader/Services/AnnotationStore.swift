import Foundation
import PDFKit

// MARK: - Annotation Store
//
// JSON-based persistence for highlights and annotations.
// One file per book: annotations/{bookId}.json
//
// ┌──────────────────────────────────────────────────────┐
// │              AnnotationStore                          │
// │                                                      │
// │  load(bookId) → BookAnnotations                      │
// │  save()                                              │
// │  addHighlight(text, page, bounds, chapter)            │
// │  updateHighlight(id, reaction, action)                │
// │  deleteHighlight(id)                                  │
// │  highlightsForPage(page) → [BookHighlight]            │
// │                                                      │
// │  Storage: ~/Library/Application Support/annotations/  │
// │  Format: Codable JSON, debounced serial queue writes  │
// └──────────────────────────────────────────────────────┘

@Observable
final class AnnotationStore {

    private(set) var annotations: BookAnnotations
    private let bookId: String
    private let saveQueue = DispatchQueue(label: "com.nightreader.annotation-store", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    private var backgroundObserver: Any?

    init(bookId: String, title: String, author: String? = nil) {
        self.bookId = bookId
        self.annotations = BookAnnotations(id: bookId, title: title, author: author)
        load()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: .appWillBackground, object: nil, queue: nil
        ) { [weak self] _ in
            self?.saveNow()
        }
    }

    deinit {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Flush pending data on dealloc
        saveNow()
    }

    // MARK: - CRUD

    func addHighlight(
        text: String,
        page: Int,
        bounds: [[CGFloat]], // [[x, y, w, h], ...] per line
        chapter: String? = nil,
        color: String = "yellow"
    ) -> BookHighlight {
        let highlight = BookHighlight(
            bookId: bookId,
            text: text,
            page: page,
            bounds: bounds,
            chapter: chapter,
            color: color
        )
        annotations.highlights.append(highlight)
        scheduleSave()
        return highlight
    }

    func updateHighlight(id: UUID, reaction: String?, action: String?) {
        guard let index = annotations.highlights.firstIndex(where: { $0.id == id }) else { return }
        if let reaction { annotations.highlights[index].reaction = reaction }
        if let action { annotations.highlights[index].action = action }
        annotations.highlights[index].updatedAt = Date()
        scheduleSave()
    }

    func deleteHighlight(id: UUID) {
        annotations.highlights.removeAll { $0.id == id }
        scheduleSave()
    }

    func setCommitted(id: UUID, committed: Bool) {
        guard let index = annotations.highlights.firstIndex(where: { $0.id == id }) else { return }
        annotations.highlights[index].committed = committed
        annotations.highlights[index].updatedAt = Date()
        scheduleSave()
    }

    // MARK: - Queries

    func highlightsForPage(_ page: Int) -> [BookHighlight] {
        annotations.highlights.filter { $0.page == page }
    }

    var allHighlights: [BookHighlight] {
        annotations.highlights.sorted { $0.page < $1.page }
    }

    var highlightsWithActions: [BookHighlight] {
        annotations.highlights.filter { $0.action != nil && !($0.action?.isEmpty ?? true) }
    }

    var highlightsWithReactions: [BookHighlight] {
        annotations.highlights.filter { $0.reaction != nil && !($0.reaction?.isEmpty ?? true) }
    }

    var highlightCount: Int { annotations.highlights.count }

    var actionCount: Int {
        annotations.highlights.filter { $0.action != nil && !($0.action?.isEmpty ?? true) }.count
    }

    // MARK: - Smart Highlights (AI)

    func addSmartHighlights(_ highlights: [SmartHighlight]) {
        annotations.smartHighlights.append(contentsOf: highlights)
        annotations.analysisCount += 1
        scheduleSave()
    }

    func smartHighlightsForChapter(_ chapterIndex: Int) -> [SmartHighlight] {
        annotations.smartHighlights.filter {
            $0.chapterIndex == chapterIndex && !$0.dismissed
        }
    }

    func isChapterAnalyzed(_ chapterIndex: Int) -> Bool {
        annotations.smartHighlights.contains { $0.chapterIndex == chapterIndex }
    }

    func dismissSmartHighlight(id: UUID) {
        guard let index = annotations.smartHighlights.firstIndex(where: { $0.id == id }) else { return }
        let type = annotations.smartHighlights[index].type
        annotations.smartHighlights[index].dismissed = true
        annotations.highlightStats.recordDismiss(type: type)
        scheduleSave()
    }

    /// Promote a smart highlight to a regular BookHighlight.
    /// Returns the new BookHighlight for UI updates.
    @discardableResult
    func promoteToHighlight(id: UUID) -> BookHighlight? {
        guard let index = annotations.smartHighlights.firstIndex(where: { $0.id == id }) else { return nil }
        let smart = annotations.smartHighlights[index]
        annotations.smartHighlights[index].savedAsHighlight = true
        annotations.highlightStats.recordSave(type: smart.type)

        let highlight = addHighlight(
            text: smart.text,
            page: smart.page,
            bounds: [],
            chapter: smart.chapterTitle,
            color: "yellow"
        )
        // Pre-fill the AI rationale as reaction
        updateHighlight(id: highlight.id, reaction: "✦ \(smart.rationale)", action: nil)
        return highlight
    }

    func clearSmartHighlightsForChapter(_ chapterIndex: Int) {
        annotations.smartHighlights.removeAll { $0.chapterIndex == chapterIndex }
        scheduleSave()
    }

    var activeSmartHighlights: [SmartHighlight] {
        annotations.smartHighlights.filter { !$0.dismissed && !$0.savedAsHighlight }
    }

    var monthlyAnalysisCount: Int { annotations.analysisCount }

    /// Type weights based on save/dismiss ratios. Returns nil if insufficient data.
    var smartHighlightTypeWeights: [SmartHighlightType: Double]? {
        annotations.highlightStats.typeWeights()
    }

    // MARK: - Chapter Reviews

    func addChapterReview(_ review: ChapterReview) {
        annotations.chapterReviews.append(review)
        scheduleSave()
    }

    func chapterReview(forChapter chapterIndex: Int) -> ChapterReview? {
        annotations.chapterReviews.first { $0.chapterIndex == chapterIndex }
    }

    func updateChapterReview(id: UUID, answerIndex: Int, answer: String) {
        guard let idx = annotations.chapterReviews.firstIndex(where: { $0.id == id }) else { return }
        guard answerIndex < annotations.chapterReviews[idx].answers.count else { return }
        annotations.chapterReviews[idx].answers[answerIndex] = answer
        scheduleSave()
    }

    func addAIFeedback(reviewId: UUID, feedback: [String], summary: String?) {
        guard let idx = annotations.chapterReviews.firstIndex(where: { $0.id == reviewId }) else { return }
        annotations.chapterReviews[idx].aiFeedback = feedback
        if let summary { annotations.chapterReviews[idx].summary = summary }
        scheduleSave()
    }

    // MARK: - Session Tracking

    var lastCreatedHighlight: BookHighlight? {
        annotations.highlights.max { $0.createdAt < $1.createdAt }
    }

    func highlightsCreatedAfter(_ date: Date) -> [BookHighlight] {
        annotations.highlights.filter { $0.createdAt > date }
    }

    // MARK: - Post-Reading Review

    func setPostReading(coreIdea: String?, whyRead: String?, mainShift: String?) {
        if annotations.postReading == nil {
            annotations.postReading = PostReadingReview()
        }
        if let coreIdea { annotations.postReading?.coreIdea = coreIdea }
        if let whyRead { annotations.postReading?.whyRead = whyRead }
        if let mainShift { annotations.postReading?.mainShift = mainShift }
        annotations.postReading?.completedAt = Date()
        scheduleSave()
    }

    // MARK: - Persistence

    private static var annotationsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("annotations")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL {
        Self.annotationsDirectory.appendingPathComponent("\(bookId).json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            annotations = try JSONDecoder().decode(BookAnnotations.self, from: data)
            // Migrate old schema versions to current
            if annotations.schemaVersion < BookAnnotations.currentSchemaVersion {
                annotations.schemaVersion = BookAnnotations.currentSchemaVersion
                performSave()
            }
        } catch {
            #if DEBUG
            print("[AnnotationStore] Failed to load \(bookId): \(error)")
            #endif
            // Corrupted file — backup and start fresh
            let backup = fileURL.appendingPathExtension("backup")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        pendingSave = workItem
        saveQueue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func performSave() {
        do {
            let data = try JSONEncoder().encode(annotations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[AnnotationStore] Failed to save \(bookId): \(error)")
            #endif
        }
    }

    /// Force immediate save (call before app termination)
    func saveNow() {
        pendingSave?.cancel()
        performSave()
    }

    /// Delete annotation file for a book (call when book is deleted)
    static func deleteAnnotations(forBookId bookId: String) {
        let url = annotationsDirectory.appendingPathComponent("\(bookId).json")
        try? FileManager.default.removeItem(at: url)
    }
}
