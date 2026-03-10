import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var fileName: String
    var dateAdded: Date
    var lastReadDate: Date?
    var lastPageIndex: Int
    var scrollOffsetY: Double
    var totalPages: Int
    var readProgress: Double
    var renderingModeRaw: String
    var cropMargin: Double

    var renderingMode: RenderingMode {
        get { RenderingMode(rawValue: renderingModeRaw) ?? .simple }
        set { renderingModeRaw = newValue.rawValue }
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
        self.renderingModeRaw = RenderingMode.simple.rawValue
        self.cropMargin = 0
    }

    var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }
}
