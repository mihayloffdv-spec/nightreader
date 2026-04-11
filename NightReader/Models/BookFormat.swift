import Foundation

// MARK: - BookFormat
//
// Identifies the file format of a book.
// Stored as a raw String in Book.formatRaw for SwiftData persistence.

enum BookFormat: String, Codable {
    case pdf
    case epub
    case fb2
}
