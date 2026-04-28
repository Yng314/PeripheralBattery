import Foundation

struct PeripheralDeviceBattery: Codable, Hashable {
    let name: String
    let symbolName: String
    let level: Int?
    let isCharging: Bool

    var shortName: String {
        if name.contains("DeathAdder") {
            return "Mouse"
        }
        if name.contains("Falchion") {
            return "Keyboard"
        }
        return name
    }

    var percentText: String {
        guard let level else {
            return "--"
        }
        return "\(level)%"
    }

    var widgetIconAssetName: String? {
        if name.contains("DeathAdder") {
            return "razerdeathadder_icon"
        }
        if name.contains("Falchion") {
            return "rogfalchion_icon"
        }
        return nil
    }

    var statusText: String {
        if isCharging {
            return "Charging"
        }
        guard level != nil else {
            return "Unavailable"
        }
        return "Battery"
    }
}
