import SwiftUI
import AppKit

struct BatteryRing: View {
    let device: PeripheralDeviceBattery
    var lineWidth: CGFloat = 7
    var iconFont: Font = .title2.weight(.semibold)

    private var progress: Double {
        guard let level = device.level else {
            return 0
        }
        return min(max(Double(level) / 100, 0), 1)
    }

    private var widgetIconImage: NSImage? {
        guard let assetName = device.widgetIconAssetName,
              let url = Bundle.main.url(forResource: assetName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.primary.opacity(0.96), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let widgetIconImage {
                Image(nsImage: widgetIconImage)
                    .resizable()
                    .scaledToFit()
                    .padding(lineWidth + 4)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: device.symbolName)
                    .font(iconFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue(device.level.map { "\($0) percent" } ?? "Not available")
    }
}
