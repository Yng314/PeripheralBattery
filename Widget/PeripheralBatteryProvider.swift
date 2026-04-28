import WidgetKit

struct PeripheralBatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeripheralBatteryEntry {
        PeripheralBatteryEntry(date: Date(), snapshot: PeripheralBatteryFixtures.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PeripheralBatteryEntry) -> Void) {
        completion(PeripheralBatteryEntry(date: Date(), snapshot: PeripheralBatteryStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PeripheralBatteryEntry>) -> Void) {
        let entry = PeripheralBatteryEntry(date: Date(), snapshot: PeripheralBatteryStore.readSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: entry.date) ?? entry.date.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
