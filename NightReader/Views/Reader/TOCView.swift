import SwiftUI

struct TOCEntry: Identifiable {
    let id = UUID()
    let label: String
    let pageIndex: Int
    let level: Int
}

struct TOCView: View {
    let chapters: [Chapter]
    let onSelectPage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [TOCEntry] = []

    var body: some View {
        NavigationStack {
            Group {
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
            .onAppear {
                entries = buildEntries()
            }
        }
    }

    private func buildEntries() -> [TOCEntry] {
        // Use pre-computed chapters (from PDF outline or auto-detected headings)
        chapters.map {
            TOCEntry(label: $0.title, pageIndex: $0.pageIndex, level: $0.level)
        }
    }
}
