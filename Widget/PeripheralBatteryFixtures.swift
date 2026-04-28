import Foundation

enum PeripheralBatteryFixtures {
    static let placeholder = PeripheralBatterySnapshot(
        mouse: PeripheralDeviceBattery(
            name: "Razer DeathAdder V3 Pro",
            symbolName: "computermouse.fill",
            level: 100,
            isCharging: false
        ),
        keyboard: PeripheralDeviceBattery(
            name: "ROG Falchion RX Low Profile",
            symbolName: "keyboard.fill",
            level: 98,
            isCharging: false
        ),
        updatedAt: Date()
    )

    static func unavailable(reason: String = "No shared data") -> PeripheralBatterySnapshot {
        PeripheralBatterySnapshot(
            mouse: PeripheralDeviceBattery(
                name: "Razer DeathAdder V3 Pro",
                symbolName: "computermouse.fill",
                level: nil,
                isCharging: false
            ),
            keyboard: PeripheralDeviceBattery(
                name: "ROG Falchion RX Low Profile",
                symbolName: "keyboard.fill",
                level: nil,
                isCharging: false
            ),
            updatedAt: Date(),
            debugMessage: reason
        )
    }
}
