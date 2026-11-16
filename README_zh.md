# LumiPluginCacheManager

📖 [English](README.md) | 中文版

缓存管理插件：在设置窗口贡献「缓存」入口，展示应用累积了多少可删除的磁盘缓存（按插件分桶明细），并提供全部清空与单桶清空。它是 [LumiProviders](https://github.com/lumi-softworks/LumiProviders) `ProviderDiskCache` 管理 API 的首个用户界面。

磁盘缓存是「删了也不影响」的加速数据（下载的图片、拉取的文件）。清空不会删除任何项目或文档——内容会按需重新下载或重建。

## 功能

- 通过 `SettingViewProviding` 注册设置入口（`id: "cache-manager"`、标题「缓存」、`shippingbox` 图标）
- 总占用概览，带刷新操作
- 按插件分桶明细（大小 · 条目数）
- 全部清空：destructive 确认对话框，说明缓存是可删除数据
- 单桶清空：走管理专用 `clearBucket(pluginID:)` API，保留生产插件自定义的淘汰策略
- 优雅降级：未注册 `SettingViewProviding` 或 `DiskCacheProviding` 时跳过入口
- 宿主可参数化插件 id（`init(id:)`），默认 Lumi 命名空间
- 本地化：English、简体中文、繁體中文、粤语、台式繁体

## 依赖

- [LumiKernel](https://github.com/lumi-softworks/LumiKernel) — `KernelCore`
- [LumiProviders](https://github.com/lumi-softworks/LumiProviders) — `ProviderDiskCache`（≥ 1.25.0）
- [LumiSettings](https://github.com/lumi-softworks/LumiSettings) — `ProviderSettingView`
- [LumiUI](https://github.com/lumi-softworks/LumiUI) — 设置脚手架 / 行 / 按钮
- [LumiLogging](https://github.com/lumi-softworks/LumiLogging) — `LumiLoggingKit`
- [LumiLocalization](https://github.com/lumi-softworks/LumiLocalization) — `LumiLocalizationKit`

## 用法

```swift
import PluginCacheManager

// 默认 ID（Lumi）
kernel.boot(CacheManagerPlugin())

// 宿主自定义 ID
kernel.boot(CacheManagerPlugin(id: "com.coffic.juicenote.plugin.cache-manager"))
```

宿主需在启动插件前注册 `DiskCacheProviding`（如 `DefaultDiskCacheProvider()`）与 `SettingViewProviding`。

## 测试

```bash
swift test
```