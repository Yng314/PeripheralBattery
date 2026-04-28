import SwiftUI
import WidgetKit

struct PeripheralBatteryWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let entry: PeripheralBatteryEntry

    private var shouldShowDebugMessage: Bool {
        entry.snapshot.mouse.level == nil && entry.snapshot.keyboard.level == nil
    }

    private static let updatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var updatedAtText: String {
        "Updated \(Self.updatedAtFormatter.string(from: entry.snapshot.updatedAt))"
    }

    var body: some View {
        GeometryReader { proxy in
            let ringSize = min(max(proxy.size.width * 0.34, 48), 62)
            let centerSpacing = ringSize + 18
            let centerX = proxy.size.width / 2
            let ringY = proxy.size.height * 0.42
            let labelY = ringY + ringSize / 2 + 24

            ZStack {
                PeripheralBatteryGlassBackground {
                    if shouldShowDebugMessage {
                        unavailableLayout
                    } else {
                        Color.clear
                    }
                }

                if !shouldShowDebugMessage {
                    if widgetFamily == .systemMedium {
                        mediumLayout(in: proxy.size)
                    } else {
                        BatteryRing(device: entry.snapshot.mouse)
                            .frame(width: ringSize, height: ringSize)
                            .position(x: centerX - centerSpacing / 2, y: ringY)

                        BatteryRing(device: entry.snapshot.keyboard)
                            .frame(width: ringSize, height: ringSize)
                            .position(x: centerX + centerSpacing / 2, y: ringY)

                        BatteryPercentLabel(device: entry.snapshot.mouse)
                            .frame(width: ringSize + 10)
                            .position(x: centerX - centerSpacing / 2, y: labelY)

                        BatteryPercentLabel(device: entry.snapshot.keyboard)
                            .frame(width: ringSize + 10)
                            .position(x: centerX + centerSpacing / 2, y: labelY)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func mediumLayout(in size: CGSize) -> some View {
        let ringSize = min(max(size.width * 0.22, 66), 80)

        HStack(spacing: 0) {
            Spacer(minLength: 0)

            mediumDevicePanel(for: entry.snapshot.mouse, ringSize: ringSize)
                .frame(width: ringSize)

            Spacer(minLength: 0)

            mediumDevicePanel(for: entry.snapshot.keyboard, ringSize: ringSize)
                .frame(width: ringSize)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 14)
    }

    private var unavailableLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Peripheral Battery")
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(entry.snapshot.debugMessage ?? "No shared data")
                .font(.caption)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.75)
                .lineLimit(widgetFamily == .systemMedium ? 4 : 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumDevicePanel(for device: PeripheralDeviceBattery, ringSize: CGFloat) -> some View {
        VStack(spacing: 12) {
            BatteryRing(
                device: device,
                lineWidth: 8,
                iconFont: .system(size: 30, weight: .semibold)
            )
            .frame(width: ringSize, height: ringSize)

            Text(device.percentText)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }
}

#Preview(as: .systemSmall) {
    PeripheralBatteryWidget()
} timeline: {
    PeripheralBatteryEntry(date: Date(), snapshot: PeripheralBatteryFixtures.placeholder)
}

#Preview(as: .systemMedium) {
    PeripheralBatteryWidget()
} timeline: {
    PeripheralBatteryEntry(date: Date(), snapshot: PeripheralBatteryFixtures.placeholder)
}
