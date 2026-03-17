import SwiftUI
import PDFKit

struct SearchBarView: View {
    @Binding var isPresented: Bool
    let document: PDFDocument?
    let onGoToSelection: (PDFSelection) -> Void

    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var currentResultIndex = 0
    @State private var isSearching = false

    struct SearchResult: Identifiable {
        let id = UUID()
        let selection: PDFSelection
        let pageIndex: Int
        let contextText: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search in document", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }

                if isSearching {
                    ProgressView()
                        .tint(.secondary)
                }

                if !searchText.isEmpty {
                    Text("\(results.isEmpty ? 0 : currentResultIndex + 1)/\(results.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button { navigateResult(delta: -1) } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(results.isEmpty)

                    Button { navigateResult(delta: 1) } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(results.isEmpty)
                }

                Button("Done") {
                    isPresented = false
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Results list
            if !results.isEmpty {
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            currentResultIndex = index
                            onGoToSelection(result.selection)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.contextText)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text("Page \(result.pageIndex + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if index == currentResultIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }
        }
        .foregroundStyle(.white)
    }

    private func performSearch() {
        guard let document, !searchText.isEmpty else {
            results = []
            return
        }

        isSearching = true
        let query = searchText
        let doc = document
        Task.detached {
            let selections = doc.findString(query, withOptions: .caseInsensitive)
            let found = selections.compactMap { selection -> SearchResult? in
                guard let page = selection.pages.first else { return nil }
                let pageIndex = doc.index(for: page)
                let context = selection.string ?? query
                return SearchResult(selection: selection, pageIndex: pageIndex, contextText: context)
            }
            await MainActor.run {
                results = found
                currentResultIndex = 0
                isSearching = false
                if let first = found.first {
                    onGoToSelection(first.selection)
                }
            }
        }
    }

    private func navigateResult(delta: Int) {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex + delta + results.count) % results.count
        onGoToSelection(results[currentResultIndex].selection)
    }
}
