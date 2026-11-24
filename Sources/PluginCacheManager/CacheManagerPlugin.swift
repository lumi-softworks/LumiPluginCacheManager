import KernelCore
import LumiUI
import ProviderDiskCache
import ProviderSettingView
import SwiftUI
import LumiLoggingKit
import os

/// 缓存管理插件
///
/// 在设置视图中注册「缓存」入口：磁盘缓存总占用、按插件分桶明细、
/// 单桶清空与全部清空。消费 `DiskCacheProviding` 的管理 API
/// （usageReport / clearAll / bucket.clear），是缓存治理的首个用户界面。
///
/// 缓存是「删了也不影响」的加速数据：清空只是让内容按需重新下载或重建。
@MainActor
public final class CacheManagerPlugin: SuperPlugin, SuperLog {
    nonisolated static let logger = Logger(subsystem: "com.coffic.lumi.plugin.cache-manager", category: "CacheManager")

    /// 默认插件标识（Lumi）。宿主 App 可传入自己的命名空间。
    public static let defaultPluginID = "com.coffic.lumi.plugin.cache-manager"

    public let id: String
    public let order = 120
    public let metadata: PluginMetadata

    /// 宿主为「非插件」缓存桶注入的显示名解析器
    /// （如 App 级 `com.coffic.cisum.cache.thumbnails` 桶）。
    private let displayNameResolver: ((String) -> String?)?

    /// 创建缓存管理插件。
    /// - Parameters:
    ///   - id: 插件唯一标识；宿主可传入自己的 id（如 `com.coffic.juicenote.*`）。
    ///   - displayNameResolver: 为不属于任何插件的缓存桶提供显示名；
    ///     返回 nil 时继续按插件 / 旧 ID 别名解析，仍未命中则显示「未知插件」。
    public init(
        id: String = CacheManagerPlugin.defaultPluginID,
        displayNameResolver: ((String) -> String?)? = nil
    ) {
        self.id = id
        self.displayNameResolver = displayNameResolver
        self.metadata = PluginMetadata(
            id: id,
            name: pluginLocalization.string("Cache Manager"),
            description: pluginLocalization.string("Manages the app's disposable disk cache: usage breakdown and cleanup."),
            category: .system,
            stage: .stable,
            policy: .alwaysOn
        )
    }

    public func onBoot(kernel: KernelCoreContainer) throws {
        guard let settings = kernel.resolveProvider((any SettingViewProviding).self) else {
            // 设置视图未注册：优雅降级，不贡献入口。
            return
        }
        guard let cache = kernel.resolveProvider((any DiskCacheProviding).self) else {
            Self.logger.error("\(Self.t)DiskCacheProviding not registered; cache manager entry skipped")
            return
        }

        let resolver = displayNameResolver
        let entry = SettingEntryItem(
            id: "cache-manager",
            title: pluginLocalization.string("Cache"),
            systemImage: "shippingbox",
            order: 60
        ) { [cache] in
            CacheManagerDetailView(
                viewModel: CacheManagerViewModel(
                    cache: cache,
                    pluginName: { pluginID in
                        resolver?(pluginID)
                            ?? Self.displayName(for: pluginID, kernel: kernel)
                    }
                )
            )
        }

        settings.addEntries([entry])
    }

    /// 把缓存桶的插件 ID 解析为插件显示名；兼容改名前的旧 ID 别名。
    static func displayName(for pluginID: String, kernel: KernelCoreContainer) -> String? {
        if let plugin = kernel.resolvePlugin(id: pluginID) {
            return plugin.metadata.name
        }
        if let currentID = kernel.legacyPluginIDAliases.first(where: { $0.value == pluginID })?.key,
           let plugin = kernel.resolvePlugin(id: currentID) {
            return plugin.metadata.name
        }
        return nil
    }

    public func onShutdown(kernel: KernelCoreContainer) throws {
        kernel.resolveProvider((any SettingViewProviding).self)?
            .removeEntries(ids: ["cache-manager"])
    }
}