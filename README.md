# LumiPluginCacheManager

📖 English | [中文版](README_zh.md)

CacheManager plugin: contributes a "Cache" entry to the settings window showing how much disposable disk cache the app has accumulated, broken down per plugin, with clear-all and per-bucket cleanup. It is the first user-facing consumer of the [LumiProviders](https://github.com/lumi-softworks/LumiProviders) `ProviderDiskCache` management API.

Disk cache is "safe to delete" acceleration data (downloaded images, fetched files). Clearing it never removes projects or documents — content is re-fetched or rebuilt on demand.

## Features

- Registers a settings entry (`id: "cache-manager"`, title "Cache", `shippingbox` icon) via `SettingViewProviding`
- Total usage overview with a refresh action
- Per-plugin bucket breakdown (size · entry count)
- Clear all cache with a destructive confirmation dialog explaining the data is disposable
- Per-bucket clear via the management-only `clearBucket(pluginID:)` API, which preserves the producer plugin's custom eviction policy
- Graceful degradation: skips the entry when `SettingViewProviding` or `DiskCacheProviding` is not registered
- Host-parameterizable plugin id (`init(id:)`), defaulting to Lumi's namespace
- Localized in English, 简体中文, 繁體中文, 粤语, 台式繁体

## Dependencies

- [LumiKernel](https://github.com/lumi-softworks/LumiKernel) — `KernelCore`
- [LumiProviders](https://github.com/lumi-softworks/LumiProviders) — `ProviderDiskCache` (≥ 1.25.0)
- [LumiSettings](https://github.com/lumi-softworks/LumiSettings) — `ProviderSettingView`
- [LumiUI](https://github.com/lumi-softworks/LumiUI) — settings scaffold / rows / buttons
- [LumiLogging](https://github.com/lumi-softworks/LumiLogging) — `LumiLoggingKit`
- [LumiLocalization](https://github.com/lumi-softworks/LumiLocalization) — `LumiLocalizationKit`

## Usage

```swift
import PluginCacheManager

// Default ID (Lumi)
kernel.boot(CacheManagerPlugin())

// Host custom ID
kernel.boot(CacheManagerPlugin(id: "com.coffic.juicenote.plugin.cache-manager"))
```

The host must register `DiskCacheProviding` (e.g. `DefaultDiskCacheProvider()`) and `SettingViewProviding` before booting plugins.

## Tests

```bash
swift test
```