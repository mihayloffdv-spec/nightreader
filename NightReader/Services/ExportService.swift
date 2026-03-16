import PDFKit
import Foundation

struct ExportService {

    static func exportAnnotationsAsText(from document: PDFDocument, title: String) -> String {
        var output = "# Annotations: \(title)\n\n"

        let highlights = AnnotationService.allHighlights(in: document)

        if highlights.isEmpty {
            output += "No highlights found.\n"
            return output
        }

        var currentPage = -1
        for info in highlights {
            if info.pageIndex != currentPage {
                currentPage = info.pageIndex
                output += "## Page \(currentPage + 1)\n\n"
            }

            let colorLabel = info.color.rawValue.capitalized
            output += "- [\(colorLabel)] \(info.text)\n"
            if let note = info.note, !note.isEmpty {
                output += "  Note: \(note)\n"
            }
            output += "\n"
        }

        return output
    }

    static func exportAnnotationsToFile(from document: PDFDocument, title: String) -> URL? {
        let text = exportAnnotationsAsText(from: document, title: title)
        let fileName = "\(title)_annotations.md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("[ExportService] Failed to write annotations file: \(error)")
            return nil
        }
    }
}
