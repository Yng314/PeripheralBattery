当前正在做什么
- 已把这次菜单栏恢复、widget 不更新、重新构建安装链路和最短排障步骤补充进 README，降低下次重复排查成本。

上次停在哪个位置
- 菜单栏侧的鼠标和键盘电量读取已恢复，主 app 已确认能把最新快照写入 `group.com.young.peripheralbattery`，并已重新安装带正确 entitlement 的 app 版本到 `/Applications`。

近期的关键决定和原因
- `defaults read group.com.young.peripheralbattery batterySnapshot` 已显示最新鼠标和键盘电量，说明主 app 写共享快照和触发 reload 的链路基本正常。
- 根目录重新构建出的 `PeripheralBattery.app` 与其中的 `PeripheralBatteryWidgetExtension.appex` 都已确认带有 `group.com.young.peripheralbattery` entitlement 和正式的开发签名。
- 用这份新产物完整替换 `/Applications/PeripheralBattery.app` 后，再次校验 `/Applications` 中的 widget appex，App Group entitlement 仍然存在，说明这次安装包身份是正确的。
- 当前经验结论已写入 README：安装到 `/Applications` 时应以根目录新构建出的 `./PeripheralBattery.app` 为准，不要默认拿 `/tmp/PeripheralBattery.app` 作为长期安装源；菜单栏正常但 widget 不更新时，先查共享快照，再重装 app，最后删除并重加 widget。
