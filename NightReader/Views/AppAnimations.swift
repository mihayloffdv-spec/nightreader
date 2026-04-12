import SwiftUI

// MARK: - App-wide animation tokens
//
// One source of truth for tap-triggered menus, sheets, and tooltips so
// everything feels consistent. Spring-based for organic motion, no
// abrupt start/stop. Tuned to feel "comfortable" — not snappy (which
// reads as urgent/anxious) and not slow (which feels laggy).

extension Animation {
    /// Primary animation for menus, toolbars, and tooltips appearing/disappearing.
    /// A soft spring that settles gently without bounce.
    static var softMenu: Animation {
        .spring(response: 0.38, dampingFraction: 0.82)
    }

    /// Slightly snappier for button taps and state toggles inside menus.
    static var softTap: Animation {
        .spring(response: 0.32, dampingFraction: 0.85)
    }

    /// Gentle fade for content swaps (mode changes, theme changes).
    /// 0.25s sits comfortably in the standard transition range — fast enough
    /// to feel responsive, slow enough that the eye registers the swap.
    static var softFade: Animation {
        .easeInOut(duration: 0.25)
    }
}

// MARK: - Reusable transitions

extension AnyTransition {
    /// Top bar / dropdown: slide down with fade
    static var softTop: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    /// Bottom bar: slide up with fade
    static var softBottom: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
}
