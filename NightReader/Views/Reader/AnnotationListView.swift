import SwiftUI
import PDFKit

struct AnnotationListView: View {
    let document: PDFDocument?
    let onSelectAnnotation: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [AnnotationInfo] = []
    @State private var editingNote: AnnotationInfo?
    @State private var noteText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if annotations.isEmpty {
                    ContentUnavailableView {
                        Label("No Highlights", systemImage: "highlighter")
                    } description: {
                        Text("Select text in the reader and tap Highlight")
                    }
                } else {
                    List {
                        ForEach(annotations) { info in
                            Button {
                                dismiss()
                                onSelectAnnotation(info.pageIndex)
                            } label: {
                                annotationRow(info)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteAnnotation(info)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    noteText = info.note ?? ""
                                    editingNote = info
                                } label: {
                                    Label("Note", systemImage: "note.text")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Edit Note", isPresented: .init(
                get: { editingNote != nil },
                set: { if !$0 { editingNote = nil } }
            )) {
                TextField("Note", text: $noteText)
                Button("Save") {
                    if let info = editingNote {
                        AnnotationService.updateNote(for: info.annotation, note: noteText)
                        if let doc = document {
                            AnnotationService.saveAnnotations(in: doc)
                        }
                        loadAnnotations()
                    }
                    editingNote = nil
                }
                Button("Cancel", role: .cancel) { editingNote = nil }
            }
            .onAppear { loadAnnotations() }
        }
    }

    private func annotationRow(_ info: AnnotationInfo) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(info.color.displayColor))
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.text.isEmpty ? "(highlight)" : info.text)
                    .font(.subheadline)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                HStack {
                    Text("Page \(info.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let note = info.note, !note.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadAnnotations() {
        guard let document else { return }
        annotations = AnnotationService.allHighlights(in: document)
    }

    private func deleteAnnotation(_ info: AnnotationInfo) {
        guard let document else { return }
        if let page = document.page(at: info.pageIndex) {
            AnnotationService.removeAnnotation(info.annotation, from: page)
            AnnotationService.saveAnnotations(in: document)
        }
        loadAnnotations()
    }
}
