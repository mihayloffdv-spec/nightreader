import SwiftUI
import PDFKit

struct TOCEntry: Identifiable {
    let id = UUID()
    let label: String
    let pageIndex: Int
    let level: Int
}

struct TOCView: View {
    let document: PDFDocument?
    let onSelectPage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                let entries = buildEntries()
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Table of Contents", systemImage: "list.bullet")
                    } description: {
                        Text("This PDF does not have a table of contents")
                    }
                } else {
                    List(entries) { entry in
                        Button {
                            dismiss()
                            onSelectPage(entry.pageIndex)
                        } label: {
                            HStack {
                                Text(entry.label)
                                    .font(.subheadline)
                                    .padding(.leading, CGFloat(entry.level) * 16)
                                Spacer()
                                Text("p.\(entry.pageIndex + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func buildEntries() -> [TOCEntry] {
        guard let document, let root = document.outlineRoot else { return [] }
        var entries: [TOCEntry] = []
        flattenOutline(root, level: 0, into: &entries)
        return entries
    }

    private func flattenOutline(_ item: PDFOutline, level: Int, into entries: inout [TOCEntry]) {
        for i in 0..<item.numberOfChildren {
            guard let child = item.child(at: i) else { continue }
            let pageIndex: Int
            if let page = child.destination?.page, let document {
                pageIndex = document.index(for: page)
            } else {
                pageIndex = 0
            }
            entries.append(TOCEntry(label: child.label ?? "Untitled", pageIndex: pageIndex, level: level))
            if child.numberOfChildren > 0 {
                flattenOutline(child, level: level + 1, into: &entries)
            }
        }
    }
}
