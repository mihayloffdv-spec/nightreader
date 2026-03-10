import SwiftUI
import PDFKit

struct SearchBarView: View {
    @Binding var isPresented: Bool
    let document: PDFDocument?
    let onGoToPage: (Int) -> Void

    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var currentResultIndex = 0

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

                if !searchText.isEmpty {
                    Text("\(results.isEmpty ? 0 : currentResultIndex + 1)/\(results.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button { navigateResult(delta: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(results.isEmpty)

                    Button { navigateResult(delta: 1) } label: {
                        Image(systemName: "chevron.down")
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
                            onGoToPage(result.pageIndex)
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

        var found: [SearchResult] = []
        let selections = document.findString(searchText, withOptions: .caseInsensitive)

        for selection in selections {
            guard let page = selection.pages.first else { continue }
            let pageIndex = document.index(for: page)
            let context = selection.string ?? searchText
            found.append(SearchResult(selection: selection, pageIndex: pageIndex, contextText: context))
        }

        results = found
        currentResultIndex = 0

        if let first = found.first {
            onGoToPage(first.pageIndex)
        }
    }

    private func navigateResult(delta: Int) {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex + delta + results.count) % results.count
        onGoToPage(results[currentResultIndex].pageIndex)
    }
}
