import Foundation
import Observation
import OSLog

enum SyncPhase: Equatable {
    case idle
    case preparing
    case syncing
    case finished
    case failed(String)
}

enum ReindexMode: Equatable, Sendable {
    case chainstate
    case full

    var restartStatusText: String {
        switch self {
        case .chainstate:
            return "Restarting kernel for chainstate reindex"
        case .full:
            return "Restarting kernel for full reindex"
        }
    }

    var openingStatusText: String {
        switch self {
        case .chainstate:
            return "Opening kernel for chainstate reindex"
        case .full:
            return "Opening kernel for full reindex"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .chainstate:
            return "Reindex Chainstate"
        case .full:
            return "Full Reindex"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .chainstate:
            return "This wipes the chainstate database and rebuilds it from the stored block files. Sync will restart."
        case .full:
            return "This wipes both the block index and chainstate databases and rebuilds them from the stored block files. Sync will restart."
        }
    }
}

struct SyncSnapshot: Equatable {
    var phase: SyncPhase = .idle
    var statusText = "Idle"
    var localHeight = 0
    var remoteHeight = 0
    var tipHash = ""

    var progressFraction: Double {
        guard remoteHeight > 0 else { return 0 }
        return min(max(Double(localHeight) / Double(remoteHeight), 0), 1)
    }

    var isComplete: Bool {
        if case .finished = phase {
            return true
        }
        return false
    }
}

@MainActor
@Observable
final class NodeViewModel {
    private static let logger = Logger(subsystem: "nl.sprovoost.Node", category: "NodeViewModel")
    private let syncEngine: NodeSyncEngine
    private var syncTask: Task<Void, Never>?
    private var isReconcilingSync = false
    private var pendingReindexMode: ReindexMode?

    var snapshot = SyncSnapshot()
    var isSyncEnabled = true
    var isNetworkEnabled = true

    init(syncEngine: NodeSyncEngine? = nil) {
        self.syncEngine = syncEngine ?? NodeSyncEngine()
    }

    nonisolated init(syncEngine: NodeSyncEngine) {
        self.syncEngine = syncEngine
    }

    func startIfNeeded() {
        Task { await reconcileSyncState() }
    }

    func prepareForTermination() async {
        isSyncEnabled = false
        await reconcileSyncState()
    }

    func toggleSync() {
        isSyncEnabled.toggle()
        Task { await reconcileSyncState() }
    }

    func toggleNetwork() {
        isNetworkEnabled.toggle()
        guard isSyncEnabled else { return }
        // Restart the running sync so it picks up the new value
        Task { await restartSync() }
    }

    func refreshKernelLogging() {
        BitcoinKernel.refreshRuntimeLogSettings()
        syncEngine.refreshLoggingSettings()
    }

    func requestReindex(_ mode: ReindexMode) {
        pendingReindexMode = mode
        isSyncEnabled = true
        snapshot.phase = .preparing
        snapshot.statusText = mode.restartStatusText
        Task { await reconcileSyncState() }
    }

    private func restartSync() async {
        guard let syncTask else { return }
        syncEngine.interrupt()
        syncTask.cancel()
        await syncTask.value
        self.syncTask = nil
        await reconcileSyncState()
    }

    private func reconcileSyncState() async {
        guard !isReconcilingSync else { return }

        isReconcilingSync = true
        defer { isReconcilingSync = false }

        while true {
            if pendingReindexMode != nil, let syncTask {
                syncEngine.interrupt()
                syncTask.cancel()
                await syncTask.value
                self.syncTask = nil
                continue
            }

            if isSyncEnabled {
                if syncTask == nil {
                    let reindexMode = pendingReindexMode
                    pendingReindexMode = nil
                    start(reindexMode: reindexMode, networkEnabled: isNetworkEnabled)
                }
                return
            }

            if let syncTask {
                syncEngine.interrupt()
                syncTask.cancel()
                await syncTask.value
                self.syncTask = nil
                markSyncStopped()
                continue
            }

            markSyncStopped()
            return
        }
    }

    private func start(reindexMode: ReindexMode?, networkEnabled: Bool = true) {
        let syncEngine = syncEngine

        syncTask = Task { [weak self] in
            defer {
                self?.markFinished()
            }

            do {
                try await syncEngine.run(reindexMode: reindexMode, networkEnabled: networkEnabled) { [weak self] snapshot in
                    await self?.apply(snapshot: snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                Self.logger.error("Node sync failed: \(String(describing: error), privacy: .public)")
                self?.applyFailure(message)
            }
        }
    }

    private func apply(snapshot: SyncSnapshot) {
        self.snapshot = snapshot
    }

    private func applyFailure(_ message: String) {
        snapshot.phase = .failed(message)
        snapshot.statusText = "Sync failed"
    }

    private func markSyncStopped() {
        guard !snapshot.isComplete else { return }
        snapshot.phase = .idle
        snapshot.statusText = "Sync stopped"
    }

    private func markFinished() {
        syncTask = nil
    }
}

struct NodeSyncEngine {
    private final class KernelRunState: @unchecked Sendable {
        private let lock = NSLock()
        private var kernel: BitcoinKernel?

        func install(_ kernel: BitcoinKernel) {
            lock.lock()
            self.kernel = kernel
            lock.unlock()
        }

        func clear(_ kernel: BitcoinKernel) {
            lock.lock()
            defer { lock.unlock() }

            if self.kernel === kernel {
                self.kernel = nil
            }
        }

        func interrupt() {
            lock.lock()
            let kernel = self.kernel
            lock.unlock()

            guard let kernel else {
                return
            }

            do {
                try kernel.interrupt()
            } catch {
                Logger(subsystem: "nl.sprovoost.Node", category: "NodeSyncEngine")
                    .error("Kernel interrupt failed: \(String(describing: error), privacy: .public)")
            }
        }

        func refreshLoggingSettings() {
            lock.lock()
            let kernel = self.kernel
            lock.unlock()

            kernel?.refreshLoggingSettings()
        }
    }

    private let client: MempoolClient
    private let storageRoot: URL
    private let runState = KernelRunState()

    nonisolated init(
        client: MempoolClient = MempoolClient(),
        storageRoot: URL = NodeSyncEngine.defaultStorageRoot()
    ) {
        self.client = client
        self.storageRoot = storageRoot
    }

    func run(reindexMode: ReindexMode? = nil, networkEnabled: Bool = true, update: @escaping @Sendable (SyncSnapshot) async -> Void) async throws {
        var snapshot = SyncSnapshot(
            phase: .preparing,
            statusText: reindexMode?.openingStatusText ?? "Opening kernel",
            localHeight: 0,
            remoteHeight: 0,
            tipHash: ""
        )
        await update(snapshot)

        guard BitcoinKernel.isSupportedOnCurrentPlatform else {
            throw BitcoinKernelError.unsupportedPlatform
        }

        let kernel = try BitcoinKernel(storageRoot: storageRoot, reindexMode: reindexMode)
        runState.install(kernel)
        defer { runState.clear(kernel) }

        let currentTip = try kernel.currentTip()

        guard networkEnabled else {
            snapshot.localHeight = currentTip.height
            snapshot.tipHash = currentTip.hash
            snapshot.phase = .finished
            snapshot.statusText = "Network disabled"
            await update(snapshot)
            return
        }

        let remoteHeight = try await client.fetchTipHeight()

        snapshot.remoteHeight = remoteHeight
        snapshot.localHeight = currentTip.height
        snapshot.tipHash = currentTip.hash
        snapshot.statusText = currentTip.height >= remoteHeight ? "Already synced" : "Syncing signet blocks"
        snapshot.phase = currentTip.height >= remoteHeight ? .finished : .syncing
        await update(snapshot)

        guard currentTip.height < remoteHeight else {
            return
        }

        let probedBatch = try await client.fetchBlocks(startingAt: remoteHeight)
        guard !probedBatch.isEmpty else {
            throw MempoolClientError.invalidBlockBatch(remoteHeight)
        }

        let batchSize = probedBatch.count
        var nextHeight = currentTip.height + 1

        while nextHeight <= remoteHeight {
            try Task.checkCancellation()

            let batchEndHeight = min(remoteHeight, nextHeight + batchSize - 1)
            snapshot.statusText = "Fetching blocks \(nextHeight)-\(batchEndHeight) of \(remoteHeight)"
            await update(snapshot)

            let batch = try await client.fetchBlocks(startingAt: batchEndHeight)
            let blocksToProcess = batch
                .filter { nextHeight ... batchEndHeight ~= $0.height }
                .sorted { $0.height < $1.height }

            let expectedCount = batchEndHeight - nextHeight + 1
            guard blocksToProcess.count == expectedCount else {
                throw MempoolClientError.invalidBlockBatch(batchEndHeight)
            }

            for block in blocksToProcess {
                try Task.checkCancellation()

                let rawBlock = try await client.fetchRawBlock(hash: block.id)
                let tip = try kernel.process(rawBlock: rawBlock, expectedHash: block.id)

                snapshot.localHeight = tip.height
                snapshot.tipHash = tip.hash
                snapshot.statusText = "Validated block \(tip.height) of \(remoteHeight)"
                await update(snapshot)
            }

            nextHeight = batchEndHeight + 1
        }

        snapshot.phase = .finished
        snapshot.statusText = "Signet sync complete"
        await update(snapshot)
    }

    func interrupt() {
        runState.interrupt()
    }

    func refreshLoggingSettings() {
        runState.refreshLoggingSettings()
    }

    nonisolated static func defaultStorageRoot() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        return baseURL.appending(path: "Node/kernel-signet", directoryHint: .isDirectory)
    }
}
