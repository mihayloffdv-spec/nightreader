import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var fileName: String
    var formatRaw: String = "pdf"  // lightweight SwiftData migration: default covers existing books
    var dateAdded: Date
    var lastReadDate: Date?
    var lastPageIndex: Int
    var scrollOffsetY: Double
    var totalPages: Int
    var readProgress: Double
    var renderingModeRaw: String
    var totalReadingTime: Double = 0
    var cropMargin: Double = 0
    var highlightCount: Int = 0
    var actionCount: Int = 0
    var bookmarksData: Data?
    @Transient private var _bookmarksCache: Set<Int>?

    var bookmarks: Set<Int> {
        get {
            if let cached = _bookmarksCache { return cached }
            guard let data = bookmarksData,
                  let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) else { return [] }
            _bookmarksCache = decoded
            return decoded
        }
        set {
            _bookmarksCache = newValue
            bookmarksData = try? JSONEncoder().encode(newValue)
        }
    }

    var renderingMode: RenderingMode {
        get { RenderingMode(rawValue: renderingModeRaw) ?? .simple }
        set { renderingModeRaw = newValue.rawValue }
    }

    var format: BookFormat {
        get { BookFormat(rawValue: formatRaw) ?? .pdf }
        set { formatRaw = newValue.rawValue }
    }

    init(
        title: String,
        author: String? = nil,
        fileName: String,
        totalPages: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.fileName = fileName
        self.dateAdded = Date()
        self.lastReadDate = nil
        self.lastPageIndex = 0
        self.scrollOffsetY = 0
        self.totalPages = totalPages
        self.readProgress = 0
        self.totalReadingTime = 0
        self.cropMargin = 0
        self.renderingModeRaw = RenderingMode.simple.rawValue
    }

    /// Директория Documents приложения.
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    /// Original file in Documents (all formats store the source file here).
    var fileURL: URL {
        Self.documentsDirectory.appendingPathComponent(fileName)
    }

    /// Format-specific content location used by content providers.
    /// PDF: same as fileURL. EPUB: extracted folder in Application Support.
    /// FB2: file in Application Support/books/fb2/.
    var contentURL: URL {
        switch format {
        case .pdf:
            return fileURL
        case .epub:
            return Self.applicationSupportDirectory
                .appendingPathComponent("books/epub/\(id.uuidString)/")
        case .fb2:
            return Self.applicationSupportDirectory
                .appendingPathComponent("books/fb2/\(fileName)")
        }
    }

    /// Formatted reading time string (e.g. "2h 15m", "45m", "< 1m").
    var formattedReadingTime: String? {
        guard totalReadingTime >= 60 else { return nil }
        let totalMinutes = Int(totalReadingTime) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
