import SwiftUI

// MARK: - Session Recap Card
//
// Shown when the user leaves the reader after a session > 30 seconds.
// Displays: duration, highlights created, actions count.

struct SessionRecapCard: View {
    let duration: TimeInterval
    let highlightCount: Int
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("Reading Session")
                .font(theme.captionFont(size: 11))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(theme.primary)

            // Duration
            Text(formattedDuration)
                .font(theme.headlineFont(size: 36))
                .foregroundStyle(theme.onSurface)

            // Stats row
            HStack(spacing: 32) {
                statItem(value: "\(highlightCount)", label: "Highlights", icon: "highlighter")
            }

            // Done button
            Button(action: onDismiss) {
                Text("Done")
                    .font(theme.labelFont(size: 14))
                    .foregroundStyle(theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(theme.accent))
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(theme.backgroundElevated)
        )
        .padding(.horizontal, 40)
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(value)
                    .font(theme.headlineFont(size: 20))
            }
            .foregroundStyle(theme.onSurface)
            Text(label)
                .font(theme.captionFont(size: 11))
                .foregroundStyle(theme.onSurfaceVariant)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}
