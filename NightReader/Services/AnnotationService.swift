import PDFKit
import UIKit

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case orange

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 0.3)
        case .green: UIColor(red: 0.0, green: 0.85, blue: 0.3, alpha: 0.3)
        case .blue: UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.3)
        case .pink: UIColor(red: 1.0, green: 0.3, blue: 0.5, alpha: 0.3)
        case .orange: UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.3)
        }
    }

    var displayColor: UIColor {
        switch self {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .orange: .systemOrange
        }
    }
}

struct AnnotationInfo: Identifiable {
    let id: String
    let text: String
    let note: String?
    let color: HighlightColor
    let pageIndex: Int
    let annotation: PDFAnnotation
}

struct AnnotationService {

    static func addHighlight(
        to selection: PDFSelection,
        in document: PDFDocument,
        color: HighlightColor = .yellow,
        note: String? = nil
    ) -> [PDFAnnotation] {
        var annotations: [PDFAnnotation] = []

        let lines = selection.selectionsByLine()

        for lineSelection in lines {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color.uiColor
                annotation.userName = color.rawValue

                if let note, !note.isEmpty {
                    annotation.contents = note
                }

                page.addAnnotation(annotation)
                annotations.append(annotation)
            }
        }

        return annotations
    }

    static func removeAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
    }

    static func updateNote(for annotation: PDFAnnotation, note: String) {
        annotation.contents = note
    }

    static func allHighlights(in document: PDFDocument) -> [AnnotationInfo] {
        var results: [AnnotationInfo] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations {
                guard annotation.type == "Highlight" else { continue }

                let color = HighlightColor(rawValue: annotation.userName ?? "") ?? .yellow
                let text = page.selection(for: annotation.bounds)?.string ?? ""

                let info = AnnotationInfo(
                    id: "\(i)-\(annotation.bounds.origin.x)-\(annotation.bounds.origin.y)",
                    text: text,
                    note: annotation.contents,
                    color: color,
                    pageIndex: i,
                    annotation: annotation
                )
                results.append(info)
            }
        }

        return results
    }

    static func saveAnnotations(in document: PDFDocument) {
        guard let url = document.documentURL else { return }
        let doc = document
        DispatchQueue.global(qos: .utility).async {
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".pdf")
            if doc.write(to: tempURL) {
                do {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
                } catch {
                    print("[AnnotationService] Failed to replace PDF: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } else {
                print("[AnnotationService] Failed to write PDF to temp file")
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }
}

