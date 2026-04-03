import SwiftUI

// MARK: - Chapter Review View (Deep Forest design)
//
// Prompted after finishing a chapter. Shows 1 question at a time,
// collects answers, shows AI feedback.
//
// ┌─────────────────────────────────────────┐
// │  Chapter 3 · The Silent Sea        1/3  │
// │  ───────────────────                    │
// │                                         │
// │  Ready to reflect on Chapter 3?         │
// │  Take a moment of stillness             │
// │                                         │
// │  What was the one idea that             │
// │  stayed with you?                       │
// │                                         │
// │  ┌─────────────────────────────────┐    │
// │  │ (answer field)                  │    │
// │  │                                 │    │
// │  └─────────────────────────────────┘    │
// │                                         │
// │  ✦ AI INSIGHT                           │
// │  A beautiful observation...             │
// │                                         │
// │  [ SAVE & CONTINUE ]                    │
// └─────────────────────────────────────────┘

struct ChapterReviewView: View {
    let chapterName: String
    let chapterNumber: Int
    let theme: Theme
    let onDismiss: () -> Void

    @State private var currentQuestion = 0
    @State private var answer = ""
    @State private var aiFeedback: String?
    @State private var isLoadingFeedback = false

    // Placeholder questions until AI integration (v2)
    private var questions: [String] {
        [
            "What was the one idea that stayed with you?",
            "How does this connect to your own experience?",
            "What would you do differently after reading this?"
        ]
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ready to reflect on \(chapterName)?")
                                .font(theme.headlineFont(size: 24))
                                .foregroundStyle(theme.textPrimary)

                            Text("Take a moment of stillness")
                                .font(theme.captionFont(size: 14))
                                .foregroundStyle(theme.textSecondary)
                        }

                        // Question
                        Text(questions[currentQuestion])
                            .font(theme.bodyFont(size: 20))
                            .foregroundStyle(theme.accent)

                        // Answer field
                        ZStack(alignment: .topLeading) {
                            if answer.isEmpty {
                                Text("Share your thoughts here...")
                                    .font(theme.bodyFont(size: 16))
                                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                                    .padding(.top, 12)
                                    .padding(.leading, 4)
                            }

                            TextEditor(text: $answer)
                                .font(theme.bodyFont(size: 16))
                                .foregroundStyle(theme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.backgroundElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(theme.surface.opacity(0.3), lineWidth: 1)
                                )
                        )

                        // AI Feedback
                        if let feedback = aiFeedback {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("✦")
                                        .foregroundStyle(theme.accent)
                                    Text("AI INSIGHT")
                                        .font(theme.captionFont(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                        .kerning(2)
                                }

                                Text(feedback)
                                    .font(theme.bodyFont(size: 14))
                                    .italic()
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(theme.backgroundElevated.opacity(0.5))
                            )
                        }

                        if isLoadingFeedback {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(theme.accent)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                // Bottom button
                VStack(spacing: 12) {
                    Button {
                        if currentQuestion < questions.count - 1 {
                            currentQuestion += 1
                            answer = ""
                            aiFeedback = nil
                        } else {
                            onDismiss()
                        }
                    } label: {
                        Text(currentQuestion < questions.count - 1 ? "SAVE & CONTINUE" : "FINISH REVIEW")
                            .font(theme.labelFont(size: 15))
                            .kerning(1)
                            .foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: theme.buttonRadius)
                                    .fill(answer.isEmpty ? theme.surface : theme.accent)
                            )
                    }
                    .disabled(answer.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHAPTER \(chapterNumber) OF 3")
                    .font(theme.captionFont(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .kerning(2)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
    }
}
