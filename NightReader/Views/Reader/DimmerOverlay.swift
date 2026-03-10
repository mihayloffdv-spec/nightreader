import SwiftUI

struct DimmerOverlay: View {
    let opacity: Double

    var body: some View {
        Color.black
            .opacity(opacity)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
