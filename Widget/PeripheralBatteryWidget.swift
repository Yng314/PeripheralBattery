import SwiftUI
import WidgetKit

struct PeripheralBatteryWidget: Widget {
    let kind = "PeripheralBatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeripheralBatteryProvider()) { entry in
            PeripheralBatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Peripheral Battery")
        .description("Shows mouse and keyboard battery levels.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
