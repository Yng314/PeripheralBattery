import Foundation

enum PeripheralBatteryStore {
    static let appGroupIdentifier = "group.com.young.peripheralbattery"
    static let snapshotKey = "batterySnapshot"

    static func readSnapshot() -> PeripheralBatterySnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return PeripheralBatteryFixtures.unavailable(reason: "Shared defaults unavailable")
        }

        if let snapshot = decodeSnapshot(from: defaults.object(forKey: snapshotKey)) {
            return snapshot
        }

        if let snapshot = decodeSnapshot(from: defaults.persistentDomain(forName: appGroupIdentifier)?[snapshotKey]) {
            return snapshot
        }

        return PeripheralBatteryFixtures.unavailable(reason: "No shared battery snapshot")
    }

    private static func decodeSnapshot(from json: String) -> PeripheralBatterySnapshot? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder.peripheralBattery.decode(PeripheralBatterySnapshot.self, from: data)
    }

    private static func decodeSnapshot(from object: Any?) -> PeripheralBatterySnapshot? {
        switch object {
        case let json as String:
            return decodeSnapshot(from: json)
        case let data as Data:
            return try? JSONDecoder.peripheralBattery.decode(PeripheralBatterySnapshot.self, from: data)
        case let dictionary as [String: Any]:
            return decodeSnapshot(fromJSONObject: dictionary)
        case let dictionary as NSDictionary:
            return decodeSnapshot(fromJSONObject: dictionary)
        default:
            return nil
        }
    }

    private static func decodeSnapshot(fromJSONObject object: Any) -> PeripheralBatterySnapshot? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }

        return try? JSONDecoder.peripheralBattery.decode(PeripheralBatterySnapshot.self, from: data)
    }
}
