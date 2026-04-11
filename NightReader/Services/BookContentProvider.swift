import UIKit

// MARK: - BookContentProvider
// BookFormat is defined in Models/BookFormat.swift
//
// Abstracts content access across PDF, EPUB, and FB2.
// "Page" means different things per format:
//   PDF  — PDF page index
//   EPUB — spine item index (stable, layout-independent)
//   FB2  — top-level <section> index (stable across re-parses)
//
// All async methods are safe to call from any actor.
// Implementations must not capture mutable state across concurrent calls.
//
//  ┌─────────────────────────────────────────────────────┐
//  │              BookContentProvider                     │
//  │                                                     │
//  │  format       — .pdf | .epub | .fb2                 │
//  │  pageCount    — spine items / sections / PDF pages  │
//  │  title        — from metadata                       │
//  │  author       — from metadata                       │
//  │  cover        — from metadata or first page         │
//  │  outline      — [Chapter] (format-native TOC)       │
//  │                                                     │
//  │  contentBlocks(forPage:) → [PositionedBlock]        │
//  │  plainText(forPage:) → String                       │
//  │    (UTF-16 offsets, stable across re-parses)        │
//  └─────────────────────────────────────────────────────┘

protocol BookContentProvider: AnyObject {
    var format: BookFormat { get }
    var pageCount: Int { get }
    var title: String? { get }
    var author: String? { get }
    var cover: UIImage? { get }
    /// Format-native chapter list. Empty if the format has no TOC metadata.
    var outline: [Chapter] { get }

    /// Returns rendered content blocks for display in ReaderModeView.
    /// PDF: delegates to PDFContentExtractor. EPUB/FB2: parsed on init, returned from cache.
    func contentBlocks(forPage index: Int) async throws -> [PositionedBlock]

    /// Returns normalized plain text for the page (whitespace-collapsed, punctuation preserved).
    /// charOffset values in PositionedBlock are UTF-16 code unit offsets into this string.
    /// Output must be stable across re-parses of the same file content.
    func plainText(forPage index: Int) async throws -> String
}
