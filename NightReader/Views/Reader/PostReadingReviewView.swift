import SwiftUI

// MARK: - Post-Reading Review
//
// Guided reflection flow after finishing a book.
// Three fields: core idea, why you read it, main shift in thinking.
// Stores via AnnotationStore.setPostReading().

struct PostReadingReviewView: View {
    @Bindable var viewModel: ReaderViewModel
    let theme: Theme
    @Environment(\.dismiss) private var dismiss

    @State private var coreIdea: String = ""
    @State private var whyRead: String = ""
    @State private var mainShift: String = ""
    @State private var currentStep: Int = 0

    private let questions = [
        ("Core Idea", "What is the main idea of this book in your own words?", "lightbulb"),
        ("Why You Read It", "What drew you to this book? What were you looking for?", "magnifyingglass"),
        ("Main Shift", "What changed in your thinking after reading this?", "arrow.triangle.2.circlepath"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Progress dots
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i <= currentStep ? theme.accent : theme.surface)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Spacer()

                    // Question
                    VStack(spacing: 16) {
                        Image(systemName: questions[currentStep].2)
                            .font(.system(size: 28))
                            .foregroundStyle(theme.accent)

                        Text(questions[currentStep].0)
                            .font(theme.captionFont(size: 11))
                            .textCase(.uppercase)
                            .tracking(2)
                            .foregroundStyle(theme.accent)

                        Text(questions[currentStep].1)
                            .font(theme.headlineFont(size: 22))
                            .foregroundStyle(theme.onSurface)
                            .multilineTextAlignment(.center)
                    }

                    // Answer field
                    TextEditor(text: currentBinding)
                        .font(theme.bodyFont(size: 16))
                        .foregroundStyle(theme.onSurface)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120, maxHeight: 200)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(theme.surfaceContainerLow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(theme.outlineVariant, lineWidth: 1)
                                )
                        )

                    Spacer()

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentStep > 0 {
                            Button {
                                withAnimation { currentStep -= 1 }
                            } label: {
                                Text("Back")
                                    .font(theme.labelFont(size: 14))
                                    .foregroundStyle(theme.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Capsule().fill(theme.surfaceContainerHigh))
                            }
                        }

                        Button {
                            if currentStep < 2 {
                                withAnimation { currentStep += 1 }
                            } else {
                                saveAndDismiss()
                            }
                        } label: {
                            Text(currentStep < 2 ? "Next" : "Complete")
                                .font(theme.labelFont(size: 14))
                                .foregroundStyle(theme.onPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(theme.accent))
                        }
                    }
                }
                .padding(32)
            }
            .navigationTitle(viewModel.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(theme.onSurfaceVariant)
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
        }
    }

    private var currentBinding: Binding<String> {
        switch currentStep {
        case 0: return $coreIdea
        case 1: return $whyRead
        default: return $mainShift
        }
    }

    private func saveAndDismiss() {
        viewModel.annotationStore?.setPostReading(
            coreIdea: coreIdea.isEmpty ? nil : coreIdea,
            whyRead: whyRead.isEmpty ? nil : whyRead,
            mainShift: mainShift.isEmpty ? nil : mainShift
        )
        dismiss()
    }
}
