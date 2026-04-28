import WidgetKit

@_cdecl("reloadPeripheralBatteryWidgetTimelines")
public func reloadPeripheralBatteryWidgetTimelines() {
    WidgetCenter.shared.reloadTimelines(ofKind: "PeripheralBatteryWidget")
}
