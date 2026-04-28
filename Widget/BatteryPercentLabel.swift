import SwiftUI

struct BatteryPercentLabel: View {
    let device: PeripheralDeviceBattery

    var body: some View {
        Text(device.percentText)
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.72)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(device.name) battery")
            .accessibilityValue(device.level.map { "\($0) percent" } ?? "Not available")
    }
}
