import Foundation
import Testing
import ProviderDiskCache
@testable import PluginCacheManager

/// CacheManagerViewModel 行为验证。
///
/// 重点覆盖仓库约定：await 后写回共享状态必须带身份（代次）校验，
/// 用延迟构造「旧请求晚到」，断言新状态不被覆盖。
@Suite("CacheManagerViewModel")
@MainActor
struct CacheManagerViewModelTests {

    private func makeReport(total: Int64, buckets: Int = 1) -> DiskCacheUsageReport {
        let usages = (0..<buckets).map {
            DiskCacheBucketUsage(pluginID: "plugin.\($0)", byteCount: total / Int64(buckets), entryCount: 1)
        }
        return DiskCacheUsageReport(buckets: usages, totalBytes: total)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("refresh 载入用量报告")
    func refreshLoadsReport() async {
        let report = makeReport(total: 1024)
        let cache = StubDiskCache(reports: [report])
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.report == report)
        #expect(viewModel.isLoading == false)
    }

    @Test("refreshAndWait 返回时报告已就绪")
    func refreshAndWaitAwaitsReport() async {
        let report = makeReport(total: 2048)
        let cache = StubDiskCache(reports: [report])
        let viewModel = CacheManagerViewModel(cache: cache)

        await viewModel.refreshAndWait()

        #expect(viewModel.report == report)
        #expect(viewModel.isLoading == false)
    }

    @Test("旧 refresh 晚到时不覆盖新报告")
    func staleRefreshIsDiscarded() async {
        let stale = makeReport(total: 111)
        let fresh = makeReport(total: 222)
        // 第一次调用延迟 200ms，第二次立即返回
        let cache = StubDiskCache(reports: [stale, fresh], delays: [200_000_000, 0])
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.refresh()
        // 确保旧任务已消费 reports[0]=stale（200ms 延迟在途），再发起新任务，
        // 使新任务确定性地消费 reports[1]=fresh，避免并发入口竞态。
        await waitUntil { cache.usageReportCallCount >= 1 }
        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.report == fresh)
    }

    @Test("clearAll 清空并刷新报告、给出反馈")
    func clearAllUpdatesReportAndFeedback() async {
        let full = makeReport(total: 4096)
        let empty = DiskCacheUsageReport.empty
        let cache = StubDiskCache(reports: [full, empty])
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.report == full)

        viewModel.clearAll()
        await waitUntil { !viewModel.isClearing }

        #expect(cache.clearAllCallCount == 1)
        #expect(viewModel.report == empty)
        #expect(viewModel.feedback != nil)
        #expect(viewModel.isClearing == false)
    }

    @Test("旧 clearAll 晚到时不覆盖新状态")
    func staleClearAllIsDiscarded() async {
        let stale = makeReport(total: 100)
        let newest = makeReport(total: 0)
        // 旧任务慢（300ms）、新任务快（50ms）：新任务先收尾并写入报告，
        // 旧任务晚到被代次校验丢弃。usageReport 按到达顺序消费报告，
        // 新任务先到故拿到 reports[0]=newest，旧任务拿到 reports[1]=stale 但被丢弃。
        let cache = StubDiskCache(
            reports: [newest, stale],
            clearAllDelays: [300_000_000, 50_000_000]
        )
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.clearAll()
        // 确保旧任务已进入 clearAll（index0，300ms 慢），再发起新任务（index1，50ms 快），
        // 新任务先收尾并消费 reports[0]=newest，旧任务晚到被代次校验丢弃。
        await waitUntil { cache.clearAllCallCount >= 1 }
        viewModel.clearAll()
        await waitUntil { !viewModel.isClearing }
        // 等第一次（慢）clearAll 也收尾
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(cache.clearAllCallCount == 2)
        #expect(viewModel.report == newest)
        #expect(viewModel.isClearing == false)
    }

    @Test("clearBucket 清空指定桶并刷新报告")
    func clearBucketClearsAndRefreshes() async {
        let before = makeReport(total: 2048, buckets: 2)
        let after = makeReport(total: 1024, buckets: 1)
        let cache = StubDiskCache(reports: [before, after])
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.report == before)

        viewModel.clearBucket(pluginID: "plugin.0")
        await waitUntil { !viewModel.isLoading }

        #expect(cache.clearedBucketIDs == ["plugin.0"])
        #expect(viewModel.report == after)
    }

    @Test("重叠 refresh 的收尾不会误关新任务的加载标记")
    func overlappingRefreshKeepsLoadingFlag() async {
        let first = makeReport(total: 1)
        let second = makeReport(total: 2)
        // 旧任务快（50ms）、新任务慢（300ms）：旧任务收尾时新任务仍在途，
        // 加载计数不得被误关。stagger 保证旧任务先消费 reports[0]=first。
        let cache = StubDiskCache(reports: [first, second], delays: [50_000_000, 300_000_000])
        let viewModel = CacheManagerViewModel(cache: cache)

        viewModel.refresh()
        await waitUntil { cache.usageReportCallCount >= 1 }
        viewModel.refresh()
        // 两个任务都在途：计数为 2
        #expect(viewModel.isLoading == true)
        // 旧任务（50ms）已收尾、新任务（300ms）仍在途 → loading 必须保持
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(viewModel.isLoading == true)
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.isLoading == false)
        #expect(viewModel.report == second)
    }
}

// MARK: - Stubs

private final class StubDiskCache: DiskCacheProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [DiskCacheUsageReport]
    private var delays: [UInt64]
    private var callIndex = 0
    private(set) var usageReportCallCount = 0
    private let clearAllDelay: UInt64
    private var clearAllDelays: [UInt64]
    private var clearAllIndex = 0
    private(set) var clearAllCallCount = 0
    private(set) var clearedBucketIDs: [String] = []

    init(
        reports: [DiskCacheUsageReport],
        delays: [UInt64] = [],
        clearAllDelay: UInt64 = 0,
        clearAllDelays: [UInt64] = []
    ) {
        self.reports = reports
        self.delays = delays
        self.clearAllDelay = clearAllDelay
        self.clearAllDelays = clearAllDelays
    }

    func usageReport() async -> DiskCacheUsageReport {
        let (delay, report) = lock.withLock {
            let index = callIndex
            callIndex += 1
            usageReportCallCount += 1
            let d = index < delays.count ? delays[index] : 0
            let r = index < reports.count ? reports[index] : (reports.last ?? .empty)
            return (d, r)
        }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return report
    }

    func clearAll() async {
        let delay = lock.withLock {
            let index = clearAllIndex
            clearAllIndex += 1
            clearAllCallCount += 1
            return index < clearAllDelays.count ? clearAllDelays[index] : clearAllDelay
        }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    func clearBucket(pluginID: String) async {
        lock.withLock { clearedBucketIDs.append(pluginID) }
    }

    func bucket(for pluginID: String, policy: DiskCachePolicy) async -> any DiskCacheBucket {
        StubBucket(pluginID: pluginID) { [weak self] id in
            self?.lock.withLock { self?.clearedBucketIDs.append(id) }
        }
    }
}

private final class StubBucket: DiskCacheBucket, @unchecked Sendable {
    let pluginID: String
    private let onClear: @Sendable (String) -> Void

    init(pluginID: String, onClear: @escaping @Sendable (String) -> Void) {
        self.pluginID = pluginID
        self.onClear = onClear
    }

    func store(_ data: Data, forKey key: String, options: DiskCacheStoreOptions) async -> Bool { true }
    func store(fileAt sourceURL: URL, forKey key: String, options: DiskCacheStoreOptions) async -> Bool { true }
    func data(forKey key: String) async -> Data? { nil }
    func fileURL(forKey key: String) async -> URL? { nil }
    func remove(forKey key: String) async {}
    func invalidate(tag: String) async {}
    func clear() async { onClear(pluginID) }
    func diskUsage() async -> Int64 { 0 }
}