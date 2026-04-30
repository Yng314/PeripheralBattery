当前正在做什么
- 本轮 README 展示图、应用图标、项目说明文档补充和 `/Applications` 安装包同步已完成。

上次停在哪个位置
- 这次会话开始时仓库没有 `CONTEXT.md`，README 仍使用旧的 widget 预览图，应用仍使用旧图标资源。

近期的关键决定和原因
- README 的组件展示改用真实桌面截图，比单独的 widget 渲染图更接近实际观感。
- 应用图标直接采用用户提供的图二，并重生成整套 `AppIcon.iconset` 和 `AppIcon.icns`，保证 README 顶部图标与应用图标保持一致。
- 使用 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 做编译验证，先确认资源替换没有破坏工程，再决定是否做签名和安装验证。
- README 已补充项目来源、当前支持设备范围，以及新增设备时需要先做 Windows 抓包和协议复现的原因与步骤，减少下次重复解释成本。
- 单纯运行 `/tmp/PeripheralBattery.app` 不会更新 `/Applications/PeripheralBattery.app` 的图标资源；如果用户查看“应用程序”目录中的图标，需要把新包显式同步到 `/Applications`。
