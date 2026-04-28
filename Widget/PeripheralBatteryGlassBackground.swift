import SwiftUI

struct PeripheralBatteryGlassBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(14)
        } else {
            content
                .padding(14)
        }
    }
}
