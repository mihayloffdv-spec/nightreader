import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case serif
    case sansSerif
    case rounded

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .serif: return .serif
        case .sansSerif: return .default
        case .rounded: return .rounded
        }
    }

    var displayName: String {
        switch self {
        case .serif: return "Serif"
        case .sansSerif: return "Sans Serif"
        case .rounded: return "Rounded"
        }
    }

    var icon: String {
        switch self {
        case .serif: return "textformat"
        case .sansSerif: return "textformat.alt"
        case .rounded: return "character"
        }
    }
}
