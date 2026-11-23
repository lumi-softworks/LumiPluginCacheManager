import Foundation
import ProviderDiskCache

/// 缓存管理视图模型。
///
/// 所有 await 后的共享状态写回都带代次校验（仓库约定）：
/// 旧请求晚到时直接丢弃，不覆盖新上下文。加载标记用计数管理，
/// 重叠操作的收尾不会误关新任务的转圈。
@MainActor
final class CacheManagerViewModel: ObservableObject {
    @Published private(set) var report: DiskCacheUsageReport = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var isClearing = false
    @Published private(set) var feedback: String?

    private let cache: any DiskCacheProviding
    private let pluginName: (String) -> String?
    private var reportGeneration = 0
    private var clearGeneration = 0
    private var loadingCount = 0

    /// - Parameter pluginName: 把缓存桶的插件 ID 解析为面向用户的插件名；
    ///   返回 nil（插件已卸载等）时回退到「未知插件」。
    init(
        cache: any DiskCacheProviding,
        pluginName: @escaping (String) -> String? = { _ in nil }
    ) {
        self.cache = cache
        self.pluginName = pluginName
    }

    /// 缓存根目录，用于在 Finder 中打开（仅 macOS 有效）。
    var cacheDirectoryURL: URL {
        if let defaultProvider = cache as? DefaultDiskCacheProvider {
            return defaultProvider.cacheRootDirectory
        }
        return DefaultDiskCacheProvider.makeDefaultCacheRootDirectory()
    }

    var totalDescription: String {
        formattedBytes(report.totalBytes)
    }

    func description(for usage: DiskCacheBucketUsage) -> String {
        String(
            format: pluginLocalization.string("%@ · %lld entries"),
            formattedBytes(usage.byteCount),
            usage.entryCount
        )
    }

    /// 分桶行的标题：插件显示名；解析不到（如插件已卸载留下的遗留缓存）时回退。
    func title(for usage: DiskCacheBucketUsage) -> String {
        pluginName(usage.pluginID) ?? pluginLocalization.string("Unknown Plugin")
    }

    func refresh() {
        reportGeneration += 1
        let generation = reportGeneration
        beginLoading()
        Task { [weak self] in
            guard let self else { return }
            await self.finishRefresh(generation: generation)
        }
    }

    /// 等待本次读取完成的刷新，供 SwiftUI `.refreshable` 使用。
    func refreshAndWait() async {
        reportGeneration += 1
        let generation = reportGeneration
        beginLoading()
        await finishRefresh(generation: generation)
    }

    private func finishRefresh(generation: Int) async {
        defer { endLoading() }
        let report = await cache.usageReport()
        guard reportGeneration == generation else { return }
        self.report = report
    }

    func clearAll() {
        clearGeneration += 1
        reportGeneration += 1
        let clearGen = clearGeneration
        let reportGen = reportGeneration
        isClearing = true
        feedback = nil
        Task { [weak self] in
            guard let self else { return }
            await self.cache.clearAll()
            let report = await self.cache.usageReport()
            guard self.clearGeneration == clearGen else { return }
            self.isClearing = false
            self.feedback = pluginLocalization.string("Cache cleared.")
            guard self.reportGeneration == reportGen else { return }
            self.report = report
        }
    }

    func clearBucket(pluginID: String) {
        reportGeneration += 1
        let generation = reportGeneration
        beginLoading()
        Task { [weak self] in
            guard let self else { return }
            defer { self.endLoading() }
            await self.cache.clearBucket(pluginID: pluginID)
            let report = await self.cache.usageReport()
            guard self.reportGeneration == generation else { return }
            self.report = report
        }
    }

    private func beginLoading() {
        loadingCount += 1
        isLoading = true
    }

    private func endLoading() {
        loadingCount = max(0, loadingCount - 1)
        isLoading = loadingCount > 0
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}