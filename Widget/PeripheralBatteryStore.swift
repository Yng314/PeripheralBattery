import Foundation

enum PeripheralBatteryStore {
    static let appGroupIdentifier = "group.com.young.peripheralbattery"
    static let snapshotKey = "batterySnapshot"
    static let snapshotFileName = "batterySnapshot.json"

    static func readSnapshot() -> PeripheralBatterySnapshot {
        var failures: [String] = []

        for url in snapshotFileURLs() {
            do {
                let snapshot = try readSnapshot(at: url)
                return snapshot
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let json = defaults.string(forKey: snapshotKey),
            let snapshot = decodeSnapshot(from: json) {
            return snapshot
        }

        return PeripheralBatteryFixtures.unavailable(reason: failures.joined(separator: " | "))
    }

    private static func snapshotFileURLs() -> [URL] {
        var urls: [URL] = []

        if let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(applicationSupportURL
                .appendingPathComponent("PeripheralBattery")
                .appendingPathComponent(snapshotFileName))
        }

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(containerURL.appendingPathComponent(snapshotFileName))
        }

        urls.append(URL(fileURLWithPath: "/Users/young/Library/Group Containers/\(appGroupIdentifier)/\(snapshotFileName)"))

        return urls
    }

    private static func readSnapshot(at url: URL) throws -> PeripheralBatterySnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.peripheralBattery.decode(PeripheralBatterySnapshot.self, from: data)
    }

    private static func decodeSnapshot(from json: String) -> PeripheralBatterySnapshot? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder.peripheralBattery.decode(PeripheralBatterySnapshot.self, from: data)
    }
}
