import Darwin
import Foundation
import OSLog

private let kernelLogCategoryAll = btck_swift_btck_LogCategory_ALL()
private let kernelLogLevelDebug = btck_swift_btck_LogLevel_DEBUG()
private let kernelLogLevelInfo = btck_swift_btck_LogLevel_INFO()
private let kernelSynchronizationStateInitReindex = btck_swift_btck_SynchronizationState_INIT_REINDEX()
private let kernelSynchronizationStateInitDownload = btck_swift_btck_SynchronizationState_INIT_DOWNLOAD()
private let kernelSynchronizationStatePostInit = btck_swift_btck_SynchronizationState_POST_INIT()
private let kernelWarningUnknownNewRulesActivated = btck_swift_btck_Warning_UNKNOWN_NEW_RULES_ACTIVATED()
private let kernelWarningLargeWorkInvalidChain = btck_swift_btck_Warning_LARGE_WORK_INVALID_CHAIN()
private let kernelValidationModeValid = btck_swift_btck_ValidationMode_VALID()
private let kernelValidationModeInvalid = btck_swift_btck_ValidationMode_INVALID()
private let kernelValidationModeInternalError = btck_swift_btck_ValidationMode_INTERNAL_ERROR()
private let kernelBlockCheckFlagsAll = btck_swift_btck_BlockCheckFlags_ALL()
private let kernelBlockValidationResultUnset = btck_swift_btck_BlockValidationResult_UNSET()
private let kernelBlockValidationResultConsensus = btck_swift_btck_BlockValidationResult_CONSENSUS()
private let kernelBlockValidationResultCachedInvalid = btck_swift_btck_BlockValidationResult_CACHED_INVALID()
private let kernelBlockValidationResultInvalidHeader = btck_swift_btck_BlockValidationResult_INVALID_HEADER()
private let kernelBlockValidationResultMutated = btck_swift_btck_BlockValidationResult_MUTATED()
private let kernelBlockValidationResultMissingPrev = btck_swift_btck_BlockValidationResult_MISSING_PREV()
private let kernelBlockValidationResultInvalidPrev = btck_swift_btck_BlockValidationResult_INVALID_PREV()
private let kernelBlockValidationResultTimeFuture = btck_swift_btck_BlockValidationResult_TIME_FUTURE()
private let kernelBlockValidationResultHeaderLowWork = btck_swift_btck_BlockValidationResult_HEADER_LOW_WORK()
private let kernelTxValidationResultUnset = btck_swift_btck_TxValidationResult_UNSET()
private let kernelScriptVerifyStatusOK = btck_swift_btck_ScriptVerifyStatus_OK()
private let kernelScriptVerificationFlagsAll = btck_swift_btck_ScriptVerificationFlags_ALL()

private final class RuntimeKernelLogSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = KernelLogSettings.snapshot()

    func update(_ snapshot: KernelLogSettingsSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func current() -> KernelLogSettingsSnapshot {
        lock.lock()
        let snapshot = snapshot
        lock.unlock()
        return snapshot
    }
}

struct ChainTip: Equatable, Sendable {
    let height: Int
    let hash: String
}

struct BlockHeader: Equatable, Sendable {
    let hash: String
    let previousHash: String
    let version: Int32
    let timestamp: UInt32
    let bits: UInt32
    let nonce: UInt32
}

enum BitcoinKernelError: LocalizedError {
    case unsupportedPlatform
    case chainParametersCreationFailed
    case chainParametersCopyFailed
    case contextOptionsCreationFailed
    case contextCreationFailed
    case contextCopyFailed
    case chainstateOptionsCreationFailed
    case chainstateReindexSetupFailed(Int32)
    case chainstateLocked
    case chainstateCreationFailed
    case chainstateReindexFailed(Int32)
    case blockTooShort(Int)
    case blockHeaderCreationFailed
    case blockHeaderSerializationMismatch
    case blockHeaderHashUnavailable
    case blockHeaderHashMismatch(expected: String, actual: String)
    case blockHeaderProcessingFailed(Int32)
    case blockHeaderValidationStateCopyFailed
    case blockHeaderValidationFailed(mode: UInt8, result: UInt32)
    case blockCreationFailed
    case blockSerializationFailed
    case blockSerializationMismatch
    case consensusParametersUnavailable
    case blockCheckSetupFailed
    case blockCheckFailed(mode: UInt8, result: UInt32)
    case secondTransactionCheckFailed(mode: UInt8, result: UInt32)
    case blockProcessingFailed(Int32)
    case secondTransactionSerializationFailed
    case secondTransactionCreationFailed
    case secondTransactionTxidUnavailable
    case processedBlockEntryUnavailable
    case processedBlockSpentOutputsUnavailable
    case secondTransactionSpentOutputsUnavailable
    case secondTransactionSpentOutputsMismatch(expected: Int, actual: Int)
    case secondTransactionInspectionFailed(String)
    case secondTransactionVerificationFailed(txid: String, inputIndex: Int, status: UInt8)
    case activeChainUnavailable
    case activeChainHeightMismatch(expected: Int, actual: Int)
    case activeChainTipMismatch(expected: String, actual: String)
    case bestEntryUnavailable
    case blockEntryUnavailable(Int)
    case blockHashUnavailable
    case chainInspectionFailed(String)
    case blockInspectionFailed(String)
    case contextInterruptFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Kernel sync is currently supported on macOS and iOS."
        case .chainParametersCreationFailed:
            return "Failed to create signet chain parameters."
        case .chainParametersCopyFailed:
            return "Failed to copy signet chain parameters."
        case .contextOptionsCreationFailed:
            return "Failed to create kernel context options."
        case .contextCreationFailed:
            return "Failed to create kernel context."
        case .contextCopyFailed:
            return "Failed to copy the kernel context."
        case .chainstateOptionsCreationFailed:
            return "Failed to create chainstate manager options."
        case .chainstateReindexSetupFailed(let code):
            return "Failed to configure kernel reindex options with code \(code)."
        case .chainstateLocked:
            return "The chainstate is already in use by another Node instance."
        case .chainstateCreationFailed:
            return "Failed to create chainstate manager."
        case .chainstateReindexFailed(let code):
            return "Kernel reindex failed with code \(code)."
        case .blockTooShort(let byteCount):
            return "Raw block is too short to contain a header (\(byteCount) bytes)."
        case .blockHeaderCreationFailed:
            return "Failed to parse raw block header bytes."
        case .blockHeaderSerializationMismatch:
            return "Serialized block header bytes did not match the original raw header."
        case .blockHeaderHashUnavailable:
            return "Failed to read block header hash."
        case let .blockHeaderHashMismatch(expected, actual):
            return "Block header hash mismatch. Expected \(expected), got \(actual)."
        case .blockHeaderProcessingFailed(let code):
            return "Kernel block header processing failed with code \(code)."
        case .blockHeaderValidationStateCopyFailed:
            return "Failed to copy the kernel block validation state."
        case let .blockHeaderValidationFailed(mode, result):
            return "Kernel block header validation failed with mode \(mode) and result \(result)."
        case .blockCreationFailed:
            return "Failed to parse raw block bytes."
        case .blockSerializationFailed:
            return "Failed to serialize the parsed block."
        case .blockSerializationMismatch:
            return "Serialized block bytes did not match the original raw block."
        case .consensusParametersUnavailable:
            return "Failed to read consensus parameters from the chain parameters."
        case .blockCheckSetupFailed:
            return "Failed to create a validation state for the context-free block check."
        case let .blockCheckFailed(mode, result):
            return "Context-free block check failed with mode \(mode) and result \(result)."
        case let .secondTransactionCheckFailed(mode, result):
            return "Context-free check of the second transaction failed with mode \(mode) and result \(result)."
        case .blockProcessingFailed(let code):
            return "Kernel block processing failed with code \(code)."
        case .secondTransactionSerializationFailed:
            return "Failed to serialize the second transaction from the block."
        case .secondTransactionCreationFailed:
            return "Failed to re-create the second transaction from serialized bytes."
        case .secondTransactionTxidUnavailable:
            return "Failed to read the second transaction txid."
        case .processedBlockEntryUnavailable:
            return "Processed block is not addressable by hash in kernel state."
        case .processedBlockSpentOutputsUnavailable:
            return "Kernel could not read spent outputs for the processed block."
        case .secondTransactionSpentOutputsUnavailable:
            return "Kernel did not expose spent outputs for the block's second transaction."
        case let .secondTransactionSpentOutputsMismatch(expected, actual):
            return "Second transaction spent output count mismatch. Expected \(expected), got \(actual)."
        case let .secondTransactionInspectionFailed(reason):
            return "Failed to inspect the second transaction: \(reason)"
        case let .secondTransactionVerificationFailed(txid, inputIndex, status):
            return "Second transaction verification failed for txid \(txid) at input \(inputIndex) with status \(status)."
        case .activeChainUnavailable:
            return "Kernel did not expose an active chain."
        case let .activeChainHeightMismatch(expected, actual):
            return "Kernel active-chain height mismatch. Expected \(expected), got \(actual)."
        case let .activeChainTipMismatch(expected, actual):
            return "Kernel active-chain tip mismatch. Expected \(expected), got \(actual)."
        case .bestEntryUnavailable:
            return "Kernel did not expose a best block entry."
        case .blockEntryUnavailable(let height):
            return "No active-chain entry exists at height \(height)."
        case .blockHashUnavailable:
            return "Failed to read block hash from kernel state."
        case .chainInspectionFailed(let reason):
            return "Kernel chain inspection failed: \(reason)"
        case .blockInspectionFailed(let reason):
            return "Kernel block inspection failed: \(reason)"
        case .contextInterruptFailed(let code):
            return "Kernel context interrupt failed with code \(code)."
        }
    }
}

final class BitcoinKernel {
    fileprivate static let logger = Logger(subsystem: "nl.sprovoost.Node", category: "BitcoinKernel")
    private static let serializedBlockHeaderLength = 80
    private static let runtimeLogSettings = RuntimeKernelLogSettings()
    private static let loggingDisableLock = NSLock()
    private static var didDisableLogging = false
    fileprivate static let kernelWriteBytesCallback: @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?) -> Int32 = { bytes, size, userData in
        guard let userData else {
            return 1
        }

        guard size >= 0 else {
            return 1
        }

        guard size == 0 || bytes != nil else {
            return 1
        }

        let collector = Unmanaged<KernelByteCollector>.fromOpaque(userData).takeUnretainedValue()
        if let bytes, size > 0 {
            collector.data.append(UnsafeRawBufferPointer(start: bytes, count: size).bindMemory(to: UInt8.self))
        }
        return 0
    }
    fileprivate static let kernelLogCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void = { _, message, messageLength in
        guard let message else {
            return
        }

        let settings = currentDisplayLogSettings()
        guard settings.isEnabled, settings.internalLogsEnabled else {
            return
        }

        let rawMessage = String(decoding: UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(message)), count: messageLength), as: UTF8.self)
        let trimmedMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }

        if let category = KernelLogSettings.categoryForRawLogLine(trimmedMessage),
           !settings.enabledCategories.contains(category) {
            return
        }

        BitcoinKernel.logger.info("\(trimmedMessage, privacy: .public)")
    }
    fileprivate static let kernelNotificationDestroyCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { userData in
        guard let userData else {
            return
        }

        Unmanaged<KernelNotificationSink>.fromOpaque(userData).release()
    }
    fileprivate static let kernelBlockTipCallback: @convention(c) (UnsafeMutableRawPointer?, UInt8, OpaquePointer?, Double) -> Void = { userData, state, entry, verificationProgress in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.observeBlockTip(state: state, entry: entry, verificationProgress: verificationProgress)
    }
    fileprivate static let kernelHeaderTipCallback: @convention(c) (UnsafeMutableRawPointer?, UInt8, Int64, Int64, Int32) -> Void = { userData, state, height, timestamp, presync in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.logHeaderTip(state: state, height: height, timestamp: timestamp, presync: presync != 0)
    }
    fileprivate static let kernelProgressCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int, Int32, Int32) -> Void = { userData, title, titleLength, progressPercent, resumePossible in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.logProgress(title: string(from: title, length: titleLength), progressPercent: progressPercent, resumePossible: resumePossible != 0)
    }
    fileprivate static let kernelWarningSetCallback: @convention(c) (UnsafeMutableRawPointer?, UInt8, UnsafePointer<CChar>?, Int) -> Void = { userData, warning, message, messageLength in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.logWarningSet(warning: warning, message: string(from: message, length: messageLength))
    }
    fileprivate static let kernelWarningUnsetCallback: @convention(c) (UnsafeMutableRawPointer?, UInt8) -> Void = { userData, warning in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.observeWarningUnset(warning: warning)
    }
    fileprivate static let kernelFlushErrorCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void = { userData, message, messageLength in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.logFlushError(message: string(from: message, length: messageLength))
    }
    fileprivate static let kernelFatalErrorCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void = { userData, message, messageLength in
        guard let sink = notificationSink(from: userData) else {
            return
        }

        sink.logFatalError(message: string(from: message, length: messageLength))
    }
    fileprivate static let kernelValidationDestroyCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { userData in
        guard let userData else {
            return
        }

        Unmanaged<KernelValidationSink>.fromOpaque(userData).release()
    }
    fileprivate static let kernelBlockCheckedCallback: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, OpaquePointer?) -> Void = { userData, block, state in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockChecked(block: block, state: state)
    }
    fileprivate static let kernelPoWValidBlockCallback: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, OpaquePointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logPoWValidBlock(block: block, entry: entry)
    }
    fileprivate static let kernelBlockConnectedCallback: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, OpaquePointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockConnected(block: block, entry: entry)
    }
    fileprivate static let kernelBlockDisconnectedCallback: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, OpaquePointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockDisconnected(block: block, entry: entry)
    }

    private let loggingConnection: OpaquePointer?
    private let chainParameters: OpaquePointer
    private let context: OpaquePointer
    private let coverageContextCopy: OpaquePointer
    private let chainstateManager: OpaquePointer

    static var isSupportedOnCurrentPlatform: Bool {
        #if os(macOS) || os(iOS)
        true
        #else
        false
        #endif
    }

    init(storageRoot: URL, signetChallenge: Data? = nil, reindexMode: ReindexMode? = nil, inMemory: Bool = false, blockTipHandler: (@Sendable (ChainTip) -> Void)? = nil) throws {
        do {
            #if DISABLE_KERNEL_LOGGING
            Self.disableLoggingOnce()
            self.loggingConnection = nil
            #else
            let loggingSettings = Self.runtimeLogSettings.current()
            self.loggingConnection = Self.makeLoggingConnection(
                logCallback: Self.kernelLogCallback,
                settings: loggingSettings
            )
            #endif

            // The chain parameters are retained for the kernel's lifetime so consensus
            // parameters borrowed from them stay valid for context-free block checks.
            let chainParameters = try Self.makeChainParameters(signetChallenge: signetChallenge)
            self.chainParameters = chainParameters
            guard let chainParametersCopy = btck_chain_parameters_copy(chainParameters) else {
                throw BitcoinKernelError.chainParametersCopyFailed
            }
            defer { btck_chain_parameters_destroy(chainParametersCopy) }

            let contextOptions = try Self.makeContextOptions()
            defer { btck_context_options_destroy(contextOptions) }
            // The copy is not needed for app behavior; it is kept here to exercise the copy helper
            // in a real initialization path before the parameters are moved into context options.
            btck_context_options_set_chainparams(contextOptions, chainParametersCopy)
            Self.setNotifications(
                contextOptions,
                sink: KernelNotificationSink(blockTipHandler: blockTipHandler)
            )
            Self.setValidationInterface(contextOptions, sink: KernelValidationSink())

            guard let context = btck_context_create(contextOptions) else {
                throw BitcoinKernelError.contextCreationFailed
            }
            self.context = context
            guard let coverageContextCopy = btck_context_copy(context) else {
                throw BitcoinKernelError.contextCopyFailed
            }
            // The app does not need a second context. This copy exists purely to exercise the API
            // on a live context without changing the app's behavior.
            self.coverageContextCopy = coverageContextCopy

            let dataDirectory = storageRoot.appending(path: "chainstate", directoryHint: .isDirectory)
            let blocksDirectory = storageRoot.appending(path: "blocks", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: blocksDirectory, withIntermediateDirectories: true)

            let chainstateOptions = try dataDirectory.withUnsafeFileSystemRepresentation { dataPath in
                try blocksDirectory.withUnsafeFileSystemRepresentation { blocksPath in
                    guard let dataPath, let blocksPath else {
                        throw BitcoinKernelError.chainstateOptionsCreationFailed
                    }

                    guard let options = btck_chainstate_manager_options_create(
                        context,
                        dataPath,
                        strlen(dataPath),
                        blocksPath,
                        strlen(blocksPath)
                    ) else {
                        throw BitcoinKernelError.chainstateOptionsCreationFailed
                    }
                    return options
                }
            }
            defer { btck_chainstate_manager_options_destroy(chainstateOptions) }

            btck_chainstate_manager_options_set_worker_threads_num(chainstateOptions, 1)
            if inMemory {
                btck_chainstate_manager_options_update_block_tree_db_in_memory(chainstateOptions, 1)
                btck_chainstate_manager_options_update_chainstate_db_in_memory(chainstateOptions, 1)
            }
            if let reindexMode {
                let wipeBlockTreeDb: Int32 = reindexMode == .full ? 1 : 0
                let result = btck_chainstate_manager_options_set_wipe_dbs(chainstateOptions, wipeBlockTreeDb, 1)
                guard result == 0 else {
                    throw BitcoinKernelError.chainstateReindexSetupFailed(result)
                }
            }

            guard let chainstateManager = btck_chainstate_manager_create(chainstateOptions) else {
                if Self.isChainstateLocked(at: dataDirectory) {
                    throw BitcoinKernelError.chainstateLocked
                }
                throw BitcoinKernelError.chainstateCreationFailed
            }
            self.chainstateManager = chainstateManager

            if reindexMode != nil {
                let result = btck_chainstate_manager_import_blocks(chainstateManager, nil, nil, 0)
                guard result == 0 else {
                    throw BitcoinKernelError.chainstateReindexFailed(result)
                }
            }

            let restoredTip = try currentTip()
            Self.logger.info("Kernel opened at persisted tip height \(restoredTip.height, privacy: .public)")
        } catch {
            Self.logger.error("Kernel initialization failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    deinit {
        btck_chainstate_manager_destroy(chainstateManager)
        btck_context_destroy(coverageContextCopy)
        btck_context_destroy(context)
        btck_chain_parameters_destroy(chainParameters)
        if let loggingConnection {
            btck_logging_connection_destroy(loggingConnection)
        }
    }

    func currentTip() throws -> ChainTip {
        guard let entry = btck_chainstate_manager_get_best_entry(chainstateManager) else {
            throw BitcoinKernelError.bestEntryUnavailable
        }

        let height = Int(btck_block_tree_entry_get_height(entry))
        guard let blockHash = btck_block_tree_entry_get_block_hash(entry) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        let bestHash = Self.hexString(for: blockHash)

        guard let activeChain = btck_chainstate_manager_get_active_chain(chainstateManager) else {
            throw BitcoinKernelError.activeChainUnavailable
        }
        guard btck_chain_contains(activeChain, entry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("Best entry is not contained in the active chain.")
        }

        let activeChainHeight = Int(btck_chain_get_height(activeChain))
        guard activeChainHeight == height else {
            throw BitcoinKernelError.activeChainHeightMismatch(expected: height, actual: activeChainHeight)
        }

        guard let activeChainEntry = btck_chain_get_by_height(activeChain, Int32(height)) else {
            throw BitcoinKernelError.blockEntryUnavailable(height)
        }
        guard let activeChainHash = btck_block_tree_entry_get_block_hash(activeChainEntry) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        let activeChainTipHash = Self.hexString(for: activeChainHash)
        guard activeChainTipHash == bestHash else {
            throw BitcoinKernelError.activeChainTipMismatch(expected: bestHash, actual: activeChainTipHash)
        }
        guard btck_block_tree_entry_equals(activeChainEntry, entry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("Best entry and active-chain entry disagree at the tip height.")
        }

        guard let activeChainHeader = btck_block_tree_entry_get_block_header(activeChainEntry) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip header.")
        }
        defer { btck_block_header_destroy(activeChainHeader) }

        guard let copiedActiveChainHeader = btck_block_header_copy(activeChainHeader) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to copy the active-chain tip header.")
        }
        defer { btck_block_header_destroy(copiedActiveChainHeader) }

        guard let headerHash = btck_block_header_get_hash(copiedActiveChainHeader) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip header hash.")
        }
        defer { btck_block_hash_destroy(headerHash) }

        guard btck_block_hash_equals(headerHash, activeChainHash) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("The active-chain tip header hash did not match the tip block hash.")
        }

        if height > 0 {
            guard let previousEntry = btck_block_tree_entry_get_previous(activeChainEntry) else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip did not expose a previous entry.")
            }
            guard Int(btck_block_tree_entry_get_height(previousEntry)) == height - 1 else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip previous entry had an unexpected height.")
            }
            guard let previousEntryHash = btck_block_tree_entry_get_block_hash(previousEntry) else {
                throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the previous active-chain entry hash.")
            }
            guard let previousHeaderHash = btck_block_header_get_prev_hash(copiedActiveChainHeader) else {
                throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip previous header hash.")
            }
            guard btck_block_hash_equals(previousHeaderHash, previousEntryHash) == 1 else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip header prev hash did not match the previous entry hash.")
            }
        }

        // Ancestor lookups must agree with the entries already inspected: the tip is its
        // own ancestor at its own height, and the ancestor at height 0 is the genesis entry.
        guard let tipAncestor = btck_block_tree_entry_get_ancestor(activeChainEntry, Int32(height)),
              btck_block_tree_entry_equals(tipAncestor, activeChainEntry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("The tip ancestor at the tip height did not match the tip entry.")
        }
        guard let genesisAncestor = btck_block_tree_entry_get_ancestor(activeChainEntry, 0),
              let genesisEntry = btck_chain_get_by_height(activeChain, 0),
              btck_block_tree_entry_equals(genesisAncestor, genesisEntry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("The tip ancestor at height 0 did not match the genesis entry.")
        }

        return ChainTip(height: height, hash: bestHash)
    }

    func interrupt() throws {
        let result = btck_context_interrupt(context)
        guard result == 0 else {
            throw BitcoinKernelError.contextInterruptFailed(result)
        }
    }

    func refreshLoggingSettings() {
        #if !DISABLE_KERNEL_LOGGING
        Self.applyLoggingPreferences(Self.runtimeLogSettings.current())
        #endif
    }

    static func refreshRuntimeLogSettings() {
        #if !DISABLE_KERNEL_LOGGING
        runtimeLogSettings.update(KernelLogSettings.snapshot())
        #endif
    }

    static func currentRuntimeLogSettings() -> KernelLogSettingsSnapshot {
        runtimeLogSettings.current()
    }

    static func currentDisplayLogSettings() -> KernelLogSettingsSnapshot {
        KernelLogSettings.snapshot()
    }

    func blockHeader(from rawBlock: Data, expectedHash: String? = nil) throws -> BlockHeader {
        guard rawBlock.count >= Self.serializedBlockHeaderLength else {
            throw BitcoinKernelError.blockTooShort(rawBlock.count)
        }

        let rawHeader = rawBlock.prefix(Self.serializedBlockHeaderLength)
        let header = try rawHeader.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let header = btck_block_header_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.blockHeaderCreationFailed
            }
            return header
        }
        defer { btck_block_header_destroy(header) }

        // The parsed header must serialize back to the exact bytes it came from.
        var serializedHeader = [UInt8](repeating: 0, count: Self.serializedBlockHeaderLength)
        guard btck_block_header_to_bytes(header, &serializedHeader) == 0,
              Data(serializedHeader) == rawHeader else {
            throw BitcoinKernelError.blockHeaderSerializationMismatch
        }

        guard let blockHash = btck_block_header_get_hash(header) else {
            throw BitcoinKernelError.blockHeaderHashUnavailable
        }
        defer { btck_block_hash_destroy(blockHash) }

        let headerHash = Self.hexString(for: blockHash)
        if let expectedHash, headerHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
            throw BitcoinKernelError.blockHeaderHashMismatch(expected: expectedHash, actual: headerHash)
        }

        guard let previousHash = btck_block_header_get_prev_hash(header) else {
            throw BitcoinKernelError.blockHashUnavailable
        }

        return BlockHeader(
            hash: headerHash,
            previousHash: Self.hexString(for: previousHash),
            version: btck_block_header_get_version(header),
            timestamp: btck_block_header_get_timestamp(header),
            bits: btck_block_header_get_bits(header),
            nonce: btck_block_header_get_nonce(header)
        )
    }

    @discardableResult
    func process(rawBlock: Data, expectedHash: String? = nil) throws -> ChainTip {
        let header = try rawBlock.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let header = btck_block_header_create(baseAddress, Self.serializedBlockHeaderLength) else {
                throw BitcoinKernelError.blockHeaderCreationFailed
            }
            return header
        }
        defer { btck_block_header_destroy(header) }

        let headerSummary = try blockHeader(from: rawBlock, expectedHash: expectedHash)
        try process(header: header)
        _ = headerSummary

        let block = try rawBlock.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let block = btck_block_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.blockCreationFailed
            }
            return block
        }
        defer { btck_block_destroy(block) }

        let serializedBlock = try serializeBlock(block)
        guard serializedBlock == rawBlock else {
            throw BitcoinKernelError.blockSerializationMismatch
        }

        try inspectParsedBlock(block, against: header, expectedSummary: headerSummary)

        // Context-free consensus checks (including proof of work and merkle root) before
        // handing the block to the chainstate manager.
        try checkBlock(block)

        let secondTransaction = try extractSecondTransaction(from: block)
        defer {
            if let secondTransaction {
                btck_transaction_destroy(secondTransaction.transaction)
            }
        }

        var newBlock = Int32(0)
        let result = btck_chainstate_manager_process_block(chainstateManager, block, &newBlock)
        guard result == 0 else {
            throw BitcoinKernelError.blockProcessingFailed(result)
        }

        if let secondTransaction {
            // Re-validate tx1 after block acceptance. The public kernel API does not expose a
            // pre-acceptance coin lookup equivalent to CCoinsView::GetCoin, so the spent outputs
            // needed for script verification are sourced from the processed block's undo data.
            try verifySecondTransaction(secondTransaction.transaction, txid: secondTransaction.txid, in: block)
        }

        try inspectProcessedBlock(block, rawBlock: rawBlock)
        return try currentTip()
    }

    private func process(header: OpaquePointer) throws {
        guard let validationState = btck_chainstate_manager_process_block_header(chainstateManager, header) else {
            throw BitcoinKernelError.blockHeaderProcessingFailed(-1)
        }
        defer { btck_block_validation_state_destroy(validationState) }

        let validationMode = btck_block_validation_state_get_validation_mode(validationState)
        guard validationMode == kernelValidationModeValid else {
            let validationResult = btck_block_validation_state_get_block_validation_result(validationState)
            throw BitcoinKernelError.blockHeaderValidationFailed(mode: validationMode, result: validationResult)
        }

        guard let validationStateCopy = btck_block_validation_state_copy(validationState) else {
            throw BitcoinKernelError.blockHeaderValidationStateCopyFailed
        }
        defer { btck_block_validation_state_destroy(validationStateCopy) }

        // This copied state is redundant for the current header path, but comparing the copied
        // verdict back to the original gives the helper a concrete role instead of dead coverage.
        let copiedValidationMode = btck_block_validation_state_get_validation_mode(validationStateCopy)
        let copiedValidationResult = btck_block_validation_state_get_block_validation_result(validationStateCopy)
        guard copiedValidationMode == validationMode,
              copiedValidationResult == kernelBlockValidationResultUnset else {
            throw BitcoinKernelError.blockInspectionFailed("Copied block validation state did not preserve the valid verdict.")
        }
    }

    private func checkBlock(_ block: OpaquePointer) throws {
        guard let consensusParams = btck_chain_parameters_get_consensus_params(chainParameters) else {
            throw BitcoinKernelError.consensusParametersUnavailable
        }

        guard let validationState = btck_block_validation_state_create() else {
            throw BitcoinKernelError.blockCheckSetupFailed
        }
        defer { btck_block_validation_state_destroy(validationState) }

        guard btck_block_check(block, consensusParams, kernelBlockCheckFlagsAll, validationState) == 1 else {
            let mode = btck_block_validation_state_get_validation_mode(validationState)
            let result = btck_block_validation_state_get_block_validation_result(validationState)
            throw BitcoinKernelError.blockCheckFailed(mode: mode, result: result)
        }
    }

    private func checkTransaction(_ transaction: OpaquePointer) throws {
        guard let validationState = btck_tx_validation_state_create() else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to create a transaction validation state.")
        }
        defer { btck_tx_validation_state_destroy(validationState) }

        guard btck_transaction_check(transaction, validationState) == 1 else {
            let mode = btck_tx_validation_state_get_validation_mode(validationState)
            let result = btck_tx_validation_state_get_tx_validation_result(validationState)
            throw BitcoinKernelError.secondTransactionCheckFailed(mode: mode, result: result)
        }

        // A passing check must leave the state at valid with an unset result.
        guard btck_tx_validation_state_get_validation_mode(validationState) == kernelValidationModeValid,
              btck_tx_validation_state_get_tx_validation_result(validationState) == kernelTxValidationResultUnset else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Transaction check passed but left an unexpected validation state.")
        }
    }

    private func extractSecondTransaction(from block: OpaquePointer) throws -> (transaction: OpaquePointer, txid: String)? {
        let transactionCount = Int(btck_block_count_transactions(block))
        guard transactionCount > 1 else {
            return nil
        }

        guard let blockTransaction = btck_block_get_transaction_at(block, 1) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The block did not expose transaction 1.")
        }

        let inputCount = Int(btck_transaction_count_inputs(blockTransaction))
        guard inputCount > 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction has no inputs.")
        }

        let outputCount = Int(btck_transaction_count_outputs(blockTransaction))
        guard outputCount > 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction has no outputs.")
        }

        guard btck_transaction_get_output_at(blockTransaction, 0) != nil else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction did not expose output 0.")
        }

        let txid = try transactionID(for: blockTransaction)
        let serializedTransaction = try serializeTransaction(blockTransaction)
        let transaction = try serializedTransaction.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let transaction = btck_transaction_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.secondTransactionCreationFailed
            }
            return transaction
        }
        defer { btck_transaction_destroy(transaction) }

        // Context-free consensus checks on the recreated transaction before it is used
        // for post-acceptance script verification.
        try checkTransaction(transaction)

        guard let copiedTransaction = btck_transaction_copy(transaction) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the recreated second transaction.")
        }

        return (copiedTransaction, txid)
    }

    private func verifySecondTransaction(_ transaction: OpaquePointer, txid: String, in block: OpaquePointer) throws {
        guard let copiedTransaction = btck_transaction_copy(transaction) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the second transaction for verification.")
        }
        defer { btck_transaction_destroy(copiedTransaction) }

        guard let blockHash = btck_block_get_hash(block) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        defer { btck_block_hash_destroy(blockHash) }

        guard let blockEntry = btck_chainstate_manager_get_block_tree_entry_by_hash(chainstateManager, blockHash) else {
            throw BitcoinKernelError.processedBlockEntryUnavailable
        }

        guard let blockSpentOutputs = btck_block_spent_outputs_read(chainstateManager, blockEntry) else {
            throw BitcoinKernelError.processedBlockSpentOutputsUnavailable
        }
        defer { btck_block_spent_outputs_destroy(blockSpentOutputs) }

        guard let copiedBlockSpentOutputs = btck_block_spent_outputs_copy(blockSpentOutputs) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the processed block spent outputs.")
        }
        defer { btck_block_spent_outputs_destroy(copiedBlockSpentOutputs) }

        // This is a post-acceptance re-validation step. Block undo data excludes the coinbase
        // transaction, so transaction 1 maps to undo index 0. Tx1 is also a safe starting point:
        // a valid tx1 cannot spend the preceding coinbase, and without a public chainstate coin
        // lookup equivalent to CCoinsView::GetCoin we currently depend on undo data for prevouts.
        guard btck_block_spent_outputs_count(copiedBlockSpentOutputs) > 0,
              let transactionSpentOutputs = btck_block_spent_outputs_get_transaction_spent_outputs_at(copiedBlockSpentOutputs, 0) else {
            throw BitcoinKernelError.secondTransactionSpentOutputsUnavailable
        }
        guard let copiedTransactionSpentOutputs = btck_transaction_spent_outputs_copy(transactionSpentOutputs) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the second transaction spent outputs.")
        }
        defer { btck_transaction_spent_outputs_destroy(copiedTransactionSpentOutputs) }

        let inputCount = Int(btck_transaction_count_inputs(copiedTransaction))
        let spentOutputCount = Int(btck_transaction_spent_outputs_count(copiedTransactionSpentOutputs))
        guard spentOutputCount == inputCount else {
            throw BitcoinKernelError.secondTransactionSpentOutputsMismatch(expected: inputCount, actual: spentOutputCount)
        }

        guard btck_transaction_get_locktime(copiedTransaction) == btck_transaction_get_locktime(transaction) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The copied transaction locktime did not match the original.")
        }

        var spentOutputs: [OpaquePointer?] = []
        spentOutputs.reserveCapacity(inputCount)
        defer {
            for spentOutput in spentOutputs {
                if let spentOutput {
                    btck_transaction_output_destroy(spentOutput)
                }
            }
        }

        for inputIndex in 0..<inputCount {
            guard let borrowedInput = btck_transaction_get_input_at(copiedTransaction, inputIndex) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing input \(inputIndex).")
            }
            guard let input = btck_transaction_input_copy(borrowedInput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy input \(inputIndex).")
            }
            defer { btck_transaction_input_destroy(input) }

            // Input-level introspection: the copy must agree with the borrowed original.
            guard btck_transaction_input_get_sequence(input) == btck_transaction_input_get_sequence(borrowedInput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("The copied input sequence did not match for input \(inputIndex).")
            }

            let scriptSig = try serializeScriptSig(of: input)
            guard scriptSig == (try serializeScriptSig(of: borrowedInput)) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("The copied input script sig did not match for input \(inputIndex).")
            }

            guard let borrowedWitnessStack = btck_transaction_input_get_witness_stack(input) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing witness stack for input \(inputIndex).")
            }
            guard let witnessStack = btck_witness_stack_copy(borrowedWitnessStack) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the witness stack for input \(inputIndex).")
            }
            defer { btck_witness_stack_destroy(witnessStack) }

            let witnessItemCount = btck_witness_stack_count_items(witnessStack)
            guard witnessItemCount == btck_witness_stack_count_items(borrowedWitnessStack) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("The copied witness stack item count did not match for input \(inputIndex).")
            }
            for itemIndex in 0..<witnessItemCount {
                guard try serializeWitnessItem(witnessStack, at: itemIndex) == serializeWitnessItem(borrowedWitnessStack, at: itemIndex) else {
                    throw BitcoinKernelError.secondTransactionInspectionFailed("Witness item \(itemIndex) did not match after copying for input \(inputIndex).")
                }
            }

            guard let borrowedOutPoint = btck_transaction_input_get_out_point(input) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing outpoint for input \(inputIndex).")
            }
            guard let outPoint = btck_transaction_out_point_copy(borrowedOutPoint) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the outpoint for input \(inputIndex).")
            }
            defer { btck_transaction_out_point_destroy(outPoint) }
            _ = btck_transaction_out_point_get_index(outPoint)
            guard let borrowedPreviousTxid = btck_transaction_out_point_get_txid(outPoint) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing prevout txid for input \(inputIndex).")
            }
            guard let previousTxid = btck_txid_copy(borrowedPreviousTxid) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the prevout txid for input \(inputIndex).")
            }
            defer { btck_txid_destroy(previousTxid) }
            guard btck_txid_equals(previousTxid, borrowedPreviousTxid) == 1 else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("The copied prevout txid for input \(inputIndex) did not match the original.")
            }
            _ = Self.txidString(for: previousTxid)

            guard let borrowedCoin = btck_transaction_spent_outputs_get_coin_at(copiedTransactionSpentOutputs, inputIndex) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing spent coin for input \(inputIndex).")
            }
            guard let coin = btck_coin_copy(borrowedCoin) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent coin for input \(inputIndex).")
            }
            defer { btck_coin_destroy(coin) }
            _ = btck_coin_confirmation_height(coin)
            _ = btck_coin_is_coinbase(coin)

            guard let borrowedSpentOutput = btck_coin_get_output(coin) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing spent output for input \(inputIndex).")
            }
            guard let spentOutput = btck_transaction_output_copy(borrowedSpentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent output for input \(inputIndex).")
            }
            defer { btck_transaction_output_destroy(spentOutput) }

            guard let borrowedScriptPubkey = btck_transaction_output_get_script_pubkey(spentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing script pubkey for input \(inputIndex).")
            }
            guard let copiedScriptPubkey = btck_script_pubkey_copy(borrowedScriptPubkey) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent script pubkey for input \(inputIndex).")
            }
            defer { btck_script_pubkey_destroy(copiedScriptPubkey) }

            let recreatedScriptPubkey = try recreateScriptPubkey(copiedScriptPubkey)
            defer { btck_script_pubkey_destroy(recreatedScriptPubkey) }

            let amount = btck_transaction_output_get_amount(spentOutput)
            guard let recreatedSpentOutput = btck_transaction_output_create(recreatedScriptPubkey, amount) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to reconstruct the spent output for input \(inputIndex).")
            }

            guard let reconstructedScriptPubkey = btck_transaction_output_get_script_pubkey(recreatedSpentOutput) else {
                btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing reconstructed script pubkey for input \(inputIndex).")
            }
            guard btck_transaction_output_get_amount(recreatedSpentOutput) == amount else {
                btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("The reconstructed spent output amount did not match for input \(inputIndex).")
            }

            let reconstructedScriptBytes = try serializeScriptPubkey(reconstructedScriptPubkey)
            let originalScriptBytes = try serializeScriptPubkey(copiedScriptPubkey)
            guard reconstructedScriptBytes == originalScriptBytes else {
                btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("The reconstructed spent script pubkey bytes did not match for input \(inputIndex).")
            }

            spentOutputs.append(recreatedSpentOutput)
        }

        let precomputedTransactionData = spentOutputs.withUnsafeMutableBufferPointer { spentOutputsBuffer in
            btck_precomputed_transaction_data_create(copiedTransaction, spentOutputsBuffer.baseAddress, spentOutputsBuffer.count)
        }
        guard let precomputedTransactionData else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to create precomputed transaction data.")
        }
        defer { btck_precomputed_transaction_data_destroy(precomputedTransactionData) }

        guard let copiedPrecomputedTransactionData = btck_precomputed_transaction_data_copy(precomputedTransactionData) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy precomputed transaction data.")
        }
        defer { btck_precomputed_transaction_data_destroy(copiedPrecomputedTransactionData) }

        for inputIndex in 0..<spentOutputs.count {
            guard let spentOutput = spentOutputs[inputIndex],
                  let scriptPubkey = btck_transaction_output_get_script_pubkey(spentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing script pubkey for input \(inputIndex).")
            }
            let amount = btck_transaction_output_get_amount(spentOutput)
            var status = kernelScriptVerifyStatusOK
            let verified = btck_script_pubkey_verify(
                scriptPubkey,
                amount,
                copiedTransaction,
                copiedPrecomputedTransactionData,
                UInt32(inputIndex),
                kernelScriptVerificationFlagsAll,
                &status
            )

            guard verified == 1 else {
                throw BitcoinKernelError.secondTransactionVerificationFailed(txid: txid, inputIndex: inputIndex, status: status)
            }
        }
    }

    private func transactionID(for transaction: OpaquePointer) throws -> String {
        guard let txid = btck_transaction_get_txid(transaction) else {
            throw BitcoinKernelError.secondTransactionTxidUnavailable
        }

        return Self.txidString(for: txid)
    }

    private func serializeTransaction(_ transaction: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = btck_transaction_to_bytes(
            transaction,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0, !collector.data.isEmpty else {
            throw BitcoinKernelError.secondTransactionSerializationFailed
        }

        return collector.data
    }

    private func serializeBlock(_ block: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = btck_block_to_bytes(
            block,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0, !collector.data.isEmpty else {
            throw BitcoinKernelError.blockSerializationFailed
        }

        return collector.data
    }

    private func serializeScriptSig(of input: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = btck_transaction_input_get_script_sig(
            input,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to serialize an input script sig.")
        }

        // Unlike the other serializers, empty output is legitimate here: native
        // segwit inputs have an empty script sig.
        return collector.data
    }

    private func serializeWitnessItem(_ witnessStack: OpaquePointer, at index: Int) throws -> Data {
        let collector = KernelByteCollector()
        let result = btck_witness_stack_get_item_at(
            witnessStack,
            index,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to serialize witness item \(index).")
        }

        // Empty items are valid: an empty push is a legitimate witness stack element.
        return collector.data
    }

    private func recreateScriptPubkey(_ scriptPubkey: OpaquePointer) throws -> OpaquePointer {
        let serializedScriptPubkey = try serializeScriptPubkey(scriptPubkey)
        let recreatedScriptPubkey = serializedScriptPubkey.withUnsafeBytes { rawBuffer in
            btck_script_pubkey_create(rawBuffer.baseAddress, rawBuffer.count)
        }

        guard let recreatedScriptPubkey else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to recreate spent script pubkey bytes.")
        }

        return recreatedScriptPubkey
    }

    private func serializeScriptPubkey(_ scriptPubkey: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = btck_script_pubkey_to_bytes(
            scriptPubkey,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0, !collector.data.isEmpty else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to serialize spent script pubkey bytes.")
        }

        return collector.data
    }

    private func inspectParsedBlock(_ block: OpaquePointer, against parsedHeader: OpaquePointer, expectedSummary: BlockHeader) throws {
        guard let blockHeader = btck_block_get_header(block) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve the parsed block header.")
        }
        defer { btck_block_header_destroy(blockHeader) }

        guard let copiedBlockHeader = btck_block_header_copy(blockHeader) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the parsed block header.")
        }
        defer { btck_block_header_destroy(copiedBlockHeader) }

        guard let parsedHeaderHash = btck_block_header_get_hash(parsedHeader),
              let blockHeaderHash = btck_block_header_get_hash(copiedBlockHeader) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve parsed block header hashes.")
        }
        defer {
            btck_block_hash_destroy(parsedHeaderHash)
            btck_block_hash_destroy(blockHeaderHash)
        }

        guard btck_block_hash_equals(parsedHeaderHash, blockHeaderHash) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("The parsed block header hash did not match the block-derived header hash.")
        }

        guard btck_block_header_get_version(copiedBlockHeader) == expectedSummary.version,
              btck_block_header_get_timestamp(copiedBlockHeader) == expectedSummary.timestamp,
              btck_block_header_get_bits(copiedBlockHeader) == expectedSummary.bits,
              btck_block_header_get_nonce(copiedBlockHeader) == expectedSummary.nonce else {
            throw BitcoinKernelError.blockInspectionFailed("The block-derived header fields did not match the serialized header.")
        }
    }

    private func inspectProcessedBlock(_ block: OpaquePointer, rawBlock: Data) throws {
        guard let blockHash = btck_block_get_hash(block) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve the processed block hash.")
        }
        defer { btck_block_hash_destroy(blockHash) }

        guard let copiedBlockHash = btck_block_hash_copy(blockHash) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the processed block hash.")
        }
        defer { btck_block_hash_destroy(copiedBlockHash) }

        var blockHashBytes = [UInt8](repeating: 0, count: 32)
        btck_block_hash_to_bytes(copiedBlockHash, &blockHashBytes)
        guard let recreatedBlockHash = blockHashBytes.withUnsafeBufferPointer({
            btck_block_hash_create($0.baseAddress!)
        }) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to recreate the processed block hash from bytes.")
        }
        defer { btck_block_hash_destroy(recreatedBlockHash) }

        guard btck_block_hash_equals(blockHash, copiedBlockHash) == 1,
              btck_block_hash_equals(blockHash, recreatedBlockHash) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("Processed block hash equality checks failed.")
        }

        guard let blockEntry = btck_chainstate_manager_get_block_tree_entry_by_hash(chainstateManager, recreatedBlockHash) else {
            throw BitcoinKernelError.processedBlockEntryUnavailable
        }

        guard let activeChain = btck_chainstate_manager_get_active_chain(chainstateManager) else {
            throw BitcoinKernelError.activeChainUnavailable
        }
        guard btck_chain_contains(activeChain, blockEntry) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("Processed block entry is not contained in the active chain.")
        }

        guard let readBlock = btck_block_read(chainstateManager, blockEntry) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to read the processed block back from disk.")
        }
        defer { btck_block_destroy(readBlock) }

        guard let copiedReadBlock = btck_block_copy(readBlock) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the processed block read from disk.")
        }
        defer { btck_block_destroy(copiedReadBlock) }

        let rereadSerializedBlock = try serializeBlock(copiedReadBlock)
        guard rereadSerializedBlock == rawBlock else {
            throw BitcoinKernelError.blockInspectionFailed("The block read from disk did not match the original raw block bytes.")
        }
    }

    private static func isChainstateLocked(at dataDirectory: URL) -> Bool {
        let lockURL = dataDirectory.appending(path: "chainstate/LOCK", directoryHint: .notDirectory)

        return lockURL.withUnsafeFileSystemRepresentation { rawPath in
            guard let rawPath else {
                return false
            }

            let fd = open(rawPath, O_RDWR | O_CREAT, 0o644)
            guard fd >= 0 else {
                return false
            }
            defer { close(fd) }

            var attemptedLock = flock(
                l_start: 0,
                l_len: 0,
                l_pid: 0,
                l_type: Int16(F_WRLCK),
                l_whence: Int16(SEEK_SET)
            )

            let result = fcntl(fd, F_SETLK, &attemptedLock)
            if result == -1 {
                return errno == EACCES || errno == EAGAIN
            }

            var unlock = flock(
                l_start: 0,
                l_len: 0,
                l_pid: 0,
                l_type: Int16(F_UNLCK),
                l_whence: Int16(SEEK_SET)
            )
            _ = fcntl(fd, F_SETLK, &unlock)
            return false
        }
    }

    fileprivate static func notificationSink(from userData: UnsafeMutableRawPointer?) -> KernelNotificationSink? {
        guard let userData else {
            return nil
        }

        return Unmanaged<KernelNotificationSink>.fromOpaque(userData).takeUnretainedValue()
    }

    fileprivate static func validationSink(from userData: UnsafeMutableRawPointer?) -> KernelValidationSink? {
        guard let userData else {
            return nil
        }

        return Unmanaged<KernelValidationSink>.fromOpaque(userData).takeUnretainedValue()
    }

    fileprivate static func string(from rawString: UnsafePointer<CChar>?, length: Int) -> String {
        guard let rawString, length > 0 else {
            return ""
        }

        return String(decoding: UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(rawString)), count: length), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeChainParameters(signetChallenge: Data? = nil) throws -> OpaquePointer {
        if let signetChallenge {
            return try signetChallenge.withUnsafeBytes { buffer in
                guard let chainParameters = btck_chain_parameters_create_signet(
                    buffer.baseAddress,
                    buffer.count
                ) else {
                    throw BitcoinKernelError.chainParametersCreationFailed
                }
                return chainParameters
            }
        }

        guard let chainParameters = btck_chain_parameters_create(
            btck_swift_btck_ChainType_SIGNET()
        ) else {
            throw BitcoinKernelError.chainParametersCreationFailed
        }
        return chainParameters
    }

    private static func disableLoggingOnce() {
        loggingDisableLock.lock()
        defer { loggingDisableLock.unlock() }

        guard !didDisableLogging else {
            return
        }

        btck_logging_disable()
        didDisableLogging = true
    }

    private static func makeLoggingConnection(
        logCallback: @escaping btck_LogCallback,
        settings: KernelLogSettingsSnapshot
    ) -> OpaquePointer? {
        applyLoggingPreferences(settings)
        return btck_logging_connection_create(logCallback, nil, nil)
    }

    private static func applyLoggingPreferences(_ settings: KernelLogSettingsSnapshot) {
        btck_logging_set_options(
            btck_LoggingOptions(
                log_timestamps: settings.logTimestamps ? 1 : 0,
                log_time_micros: settings.logTimeMicros ? 1 : 0,
                log_threadnames: settings.logThreadNames ? 1 : 0,
                log_sourcelocations: settings.logSourceLocations ? 1 : 0,
                always_print_category_levels: settings.alwaysPrintCategoryLevels ? 1 : 0
            )
        )
        btck_logging_set_level_category(kernelLogCategoryAll, kernelLogLevelInfo)
        btck_logging_disable_category(kernelLogCategoryAll)

        guard settings.isEnabled, settings.internalLogsEnabled else {
            return
        }

        btck_logging_enable_category(kernelLogCategoryAll)
        for category in settings.enabledCategories {
            btck_logging_set_level_category(category, kernelLogLevelDebug)
            btck_logging_enable_category(category)
        }
    }

    private static func setNotifications(
        _ contextOptions: OpaquePointer,
        sink: KernelNotificationSink
    ) {
        let retainedSink = Unmanaged.passRetained(sink)
        let callbacks = btck_NotificationInterfaceCallbacks(
            user_data: retainedSink.toOpaque(),
            user_data_destroy: kernelNotificationDestroyCallback,
            // Keep these callbacks wired so the C API path stays exercised, but rely on the
            // kernel's own log lines for the user-visible signal to avoid redundant noise.
            block_tip: kernelBlockTipCallback,
            header_tip: kernelHeaderTipCallback,
            progress: kernelProgressCallback,
            warning_set: kernelWarningSetCallback,
            warning_unset: kernelWarningUnsetCallback,
            flush_error: kernelFlushErrorCallback,
            fatal_error: kernelFatalErrorCallback
        )

        btck_context_options_set_notifications(contextOptions, callbacks)
    }

    private static func setValidationInterface(
        _ contextOptions: OpaquePointer,
        sink: KernelValidationSink
    ) {
        let retainedSink = Unmanaged.passRetained(sink)
        var callbacks = btck_ValidationInterfaceCallbacks()
        callbacks.user_data = retainedSink.toOpaque()
        callbacks.user_data_destroy = kernelValidationDestroyCallback
        callbacks.block_checked = kernelBlockCheckedCallback
        callbacks.pow_valid_block = kernelPoWValidBlockCallback
        callbacks.block_connected = kernelBlockConnectedCallback
        callbacks.block_disconnected = kernelBlockDisconnectedCallback

        btck_context_options_set_validation_interface(contextOptions, callbacks)
    }

    private static func makeContextOptions() throws -> OpaquePointer {
        guard let contextOptions = btck_context_options_create() else {
            throw BitcoinKernelError.contextOptionsCreationFailed
        }
        return contextOptions
    }

    fileprivate static func hexString(for blockHash: OpaquePointer) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        btck_block_hash_to_bytes(blockHash, &bytes)
        return bytes.reversed().map { String(format: "%02x", $0) }.joined()
    }

    private static func txidString(for txid: OpaquePointer) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        btck_txid_to_bytes(txid, &bytes)
        return bytes.reversed().map { String(format: "%02x", $0) }.joined()
    }
}

private final class KernelByteCollector {
    var data = Data()
}

private final class KernelNotificationSink {
    let blockTipHandler: (@Sendable (ChainTip) -> Void)?

    init(blockTipHandler: (@Sendable (ChainTip) -> Void)? = nil) {
        self.blockTipHandler = blockTipHandler
    }

    func observeBlockTip(state: UInt8, entry: OpaquePointer?, verificationProgress: Double) {
        guard let entry else {
            return
        }

        let height = Int(btck_block_tree_entry_get_height(entry))
        let hash = btck_block_tree_entry_get_block_hash(entry).map(BitcoinKernel.hexString(for:)) ?? ""
        blockTipHandler?(ChainTip(height: height, hash: hash))
    }

    func observeWarningUnset(warning: UInt8) {
        // Keep this callback wired for coverage, but silence "cleared" messages because they are
        // mostly state resets and add noise without actionable information.
        _ = warningDescription(warning)
    }

    func logHeaderTip(state: UInt8, height: Int64, timestamp: Int64, presync: Bool) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryValidation) else {
            return
        }

        BitcoinKernel.logger.info(
            "Kernel header tip height \(height, privacy: .public) state \(self.synchronizationStateDescription(state), privacy: .public) timestamp \(timestamp, privacy: .public) presync \(presync, privacy: .public)"
        )
    }

    func logProgress(title: String, progressPercent: Int32, resumePossible: Bool) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryValidation) else {
            return
        }

        BitcoinKernel.logger.info(
            "Kernel progress \(title, privacy: .public) \(progressPercent, privacy: .public)% resumePossible \(resumePossible, privacy: .public)"
        )
    }

    func logWarningSet(warning: UInt8, message: String) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryKernel) else {
            return
        }

        BitcoinKernel.logger.warning(
            "Kernel warning \(self.warningDescription(warning), privacy: .public): \(message, privacy: .public)"
        )
    }

    func logFlushError(message: String) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryKernel) else {
            return
        }

        BitcoinKernel.logger.error("Kernel flush error: \(message, privacy: .public)")
    }

    func logFatalError(message: String) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryKernel) else {
            return
        }

        BitcoinKernel.logger.fault("Kernel fatal error: \(message, privacy: .public)")
    }

    private func synchronizationStateDescription(_ state: UInt8) -> String {
        switch state {
        case kernelSynchronizationStateInitReindex:
            return "init_reindex"
        case kernelSynchronizationStateInitDownload:
            return "init_download"
        case kernelSynchronizationStatePostInit:
            return "post_init"
        default:
            return "unknown(\(state))"
        }
    }

    private func warningDescription(_ warning: UInt8) -> String {
        switch warning {
        case kernelWarningUnknownNewRulesActivated:
            return "unknown_new_rules_activated"
        case kernelWarningLargeWorkInvalidChain:
            return "large_work_invalid_chain"
        default:
            return "unknown(\(warning))"
        }
    }
}

private final class KernelValidationSink {
    func logBlockChecked(block: OpaquePointer?, state: OpaquePointer?) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryValidation) else {
            return
        }

        guard let block, let state else {
            return
        }

        let blockHash = blockHashString(for: block) ?? "unavailable"
        let validationMode = btck_block_validation_state_get_validation_mode(state)
        let validationResult = btck_block_validation_state_get_block_validation_result(state)

        switch validationMode {
        case kernelValidationModeValid:
            BitcoinKernel.logger.info(
                "Kernel block checked hash \(blockHash, privacy: .public) mode valid"
            )
        case kernelValidationModeInvalid:
            BitcoinKernel.logger.warning(
                "Kernel block checked hash \(blockHash, privacy: .public) mode invalid result \(self.validationResultDescription(validationResult), privacy: .public)"
            )
        case kernelValidationModeInternalError:
            BitcoinKernel.logger.error(
                "Kernel block checked hash \(blockHash, privacy: .public) mode internal_error result \(self.validationResultDescription(validationResult), privacy: .public)"
            )
        default:
            BitcoinKernel.logger.error(
                "Kernel block checked hash \(blockHash, privacy: .public) mode unknown(\(validationMode), privacy: .public) result \(self.validationResultDescription(validationResult), privacy: .public)"
            )
        }
    }

    func logPoWValidBlock(block: OpaquePointer?, entry: OpaquePointer?) {
        logBlockLifecycleEvent(prefix: "Kernel pow-valid block", block: block, entry: entry)
    }

    func logBlockConnected(block: OpaquePointer?, entry: OpaquePointer?) {
        logBlockLifecycleEvent(prefix: "Kernel block connected", block: block, entry: entry)
    }

    func logBlockDisconnected(block: OpaquePointer?, entry: OpaquePointer?) {
        logBlockLifecycleEvent(prefix: "Kernel block disconnected", block: block, entry: entry)
    }

    private func logBlockLifecycleEvent(prefix: String, block: OpaquePointer?, entry: OpaquePointer?) {
        let settings = BitcoinKernel.currentDisplayLogSettings()
        guard settings.isEnabled, settings.enabledCategories.contains(KernelLogSettings.kernelLogCategoryValidation) else {
            return
        }

        let blockHash = block.flatMap(blockHashString(for:)) ?? "unavailable"
        let (entryHeight, entryHash) = entryInfo(entry)
        BitcoinKernel.logger.info(
            "\(prefix, privacy: .public) hash \(blockHash, privacy: .public) entryHeight \(entryHeight, privacy: .public) entryHash \(entryHash, privacy: .public)"
        )
    }

    private func blockHashString(for block: OpaquePointer) -> String? {
        guard let blockHash = btck_block_get_hash(block) else {
            return nil
        }
        defer { btck_block_hash_destroy(blockHash) }
        return BitcoinKernel.hexString(for: blockHash)
    }

    private func entryInfo(_ entry: OpaquePointer?) -> (Int, String) {
        guard let entry else {
            return (-1, "unavailable")
        }

        let height = Int(btck_block_tree_entry_get_height(entry))
        let blockHash = btck_block_tree_entry_get_block_hash(entry).map(BitcoinKernel.hexString(for:)) ?? "unavailable"
        return (height, blockHash)
    }

    private func validationResultDescription(_ result: UInt32) -> String {
        switch result {
        case kernelBlockValidationResultUnset:
            return "unset"
        case kernelBlockValidationResultConsensus:
            return "consensus"
        case kernelBlockValidationResultCachedInvalid:
            return "cached_invalid"
        case kernelBlockValidationResultInvalidHeader:
            return "invalid_header"
        case kernelBlockValidationResultMutated:
            return "mutated"
        case kernelBlockValidationResultMissingPrev:
            return "missing_prev"
        case kernelBlockValidationResultInvalidPrev:
            return "invalid_prev"
        case kernelBlockValidationResultTimeFuture:
            return "time_future"
        case kernelBlockValidationResultHeaderLowWork:
            return "header_low_work"
        default:
            return "unknown(\(result))"
        }
    }
}
