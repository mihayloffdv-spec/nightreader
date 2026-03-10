import Foundation

enum RenderingMode: String, CaseIterable, Identifiable {
    case off
    case simple
    case smart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .simple: "Simple"
        case .smart: "Smart"
        }
    }
}
