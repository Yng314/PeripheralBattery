import Foundation

struct PeripheralBatterySnapshot: Codable, Hashable {
    let mouse: PeripheralDeviceBattery
    let keyboard: PeripheralDeviceBattery
    let updatedAt: Date
    let debugMessage: String?

    init(mouse: PeripheralDeviceBattery,
         keyboard: PeripheralDeviceBattery,
         updatedAt: Date,
         debugMessage: String? = nil) {
        self.mouse = mouse
        self.keyboard = keyboard
        self.updatedAt = updatedAt
        self.debugMessage = debugMessage
    }
}
