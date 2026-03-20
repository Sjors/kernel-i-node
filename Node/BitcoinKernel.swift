import Darwin
import Foundation
import OSLog

private let kernelLogCategoryAll: UInt8 = 0
private let kernelLogLevelInfo: UInt8 = 2
private let kernelSynchronizationStateInitReindex: UInt8 = 0
private let kernelSynchronizationStateInitDownload: UInt8 = 1
private let kernelSynchronizationStatePostInit: UInt8 = 2
private let kernelWarningUnknownNewRulesActivated: UInt8 = 0
private let kernelWarningLargeWorkInvalidChain: UInt8 = 1
private let kernelValidationModeValid: UInt8 = 0
private let kernelValidationModeInvalid: UInt8 = 1
private let kernelValidationModeInternalError: UInt8 = 2
private let kernelScriptVerifyStatusOK: UInt8 = 0
private let kernelScriptVerificationFlagsAll: UInt32 =
    (1 << 0) |
    (1 << 2) |
    (1 << 4) |
    (1 << 9) |
    (1 << 10) |
    (1 << 11) |
    (1 << 17)

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
    case libraryNotFound([String])
    case libraryOpenFailed(String)
    case symbolMissing(String)
    case unsupportedPlatform
    case chainParametersCreationFailed
    case contextOptionsCreationFailed
    case contextCreationFailed
    case chainstateOptionsCreationFailed
    case chainstateLocked
    case chainstateCreationFailed
    case blockTooShort(Int)
    case blockHeaderCreationFailed
    case blockHeaderHashUnavailable
    case blockHeaderHashMismatch(expected: String, actual: String)
    case blockHeaderProcessingFailed(Int32)
    case blockHeaderValidationFailed(mode: UInt8, result: UInt32)
    case blockCreationFailed
    case blockSerializationFailed
    case blockSerializationMismatch
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
        case .libraryNotFound(let paths):
            return "libbitcoinkernel could not be found. Checked: \(paths.joined(separator: ", "))"
        case .libraryOpenFailed(let message):
            return "Failed to open libbitcoinkernel: \(message)"
        case .symbolMissing(let symbol):
            return "Missing libbitcoinkernel symbol: \(symbol)"
        case .unsupportedPlatform:
            return "Kernel sync is currently supported on macOS and iOS."
        case .chainParametersCreationFailed:
            return "Failed to create signet chain parameters."
        case .contextOptionsCreationFailed:
            return "Failed to create kernel context options."
        case .contextCreationFailed:
            return "Failed to create kernel context."
        case .chainstateOptionsCreationFailed:
            return "Failed to create chainstate manager options."
        case .chainstateLocked:
            return "The chainstate is already in use by another Node instance."
        case .chainstateCreationFailed:
            return "Failed to create chainstate manager."
        case .blockTooShort(let byteCount):
            return "Raw block is too short to contain a header (\(byteCount) bytes)."
        case .blockHeaderCreationFailed:
            return "Failed to parse raw block header bytes."
        case .blockHeaderHashUnavailable:
            return "Failed to read block header hash."
        case let .blockHeaderHashMismatch(expected, actual):
            return "Block header hash mismatch. Expected \(expected), got \(actual)."
        case .blockHeaderProcessingFailed(let code):
            return "Kernel block header processing failed with code \(code)."
        case let .blockHeaderValidationFailed(mode, result):
            return "Kernel block header validation failed with mode \(mode) and result \(result)."
        case .blockCreationFailed:
            return "Failed to parse raw block bytes."
        case .blockSerializationFailed:
            return "Failed to serialize the parsed block."
        case .blockSerializationMismatch:
            return "Serialized block bytes did not match the original raw block."
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

        let rawMessage = String(decoding: UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(message)), count: messageLength), as: UTF8.self)
        let trimmedMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
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
    fileprivate static let kernelBlockTipCallback: @convention(c) (UnsafeMutableRawPointer?, UInt8, UnsafeRawPointer?, Double) -> Void = { userData, state, entry, verificationProgress in
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
    fileprivate static let kernelBlockCheckedCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { userData, block, state in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockChecked(block: block, state: state)
    }
    fileprivate static let kernelPoWValidBlockCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logPoWValidBlock(block: block, entry: entry)
    }
    fileprivate static let kernelBlockConnectedCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockConnected(block: block, entry: entry)
    }
    fileprivate static let kernelBlockDisconnectedCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { userData, block, entry in
        guard let sink = validationSink(from: userData) else {
            return
        }

        sink.logBlockDisconnected(block: block, entry: entry)
    }

    private let library: LoadedBitcoinKernel
    private let loggingConnection: OpaquePointer?
    private let context: OpaquePointer
    private let chainstateManager: OpaquePointer

    static var isSupportedOnCurrentPlatform: Bool {
        #if os(macOS) || os(iOS)
        true
        #else
        false
        #endif
    }

    init(storageRoot: URL) throws {
        do {
            let library = try LoadedBitcoinKernel()
            self.library = library
            self.loggingConnection = library.makeLoggingConnection(logCallback: Self.kernelLogCallback)

            let chainParameters = try library.makeChainParameters()
            defer { library.btck_chain_parameters_destroy(chainParameters) }

            let contextOptions = try library.makeContextOptions()
            defer { library.btck_context_options_destroy(contextOptions) }
            library.btck_context_options_set_chainparams(contextOptions, chainParameters)
            library.setNotifications(contextOptions, sink: KernelNotificationSink(library: library))
            library.setValidationInterface(contextOptions, sink: KernelValidationSink(library: library))

            guard let context = library.btck_context_create(contextOptions) else {
                throw BitcoinKernelError.contextCreationFailed
            }
            self.context = context

            let dataDirectory = storageRoot.appending(path: "chainstate", directoryHint: .isDirectory)
            let blocksDirectory = storageRoot.appending(path: "blocks", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: blocksDirectory, withIntermediateDirectories: true)

            let chainstateOptions = try dataDirectory.withUnsafeFileSystemRepresentation { dataPath in
                try blocksDirectory.withUnsafeFileSystemRepresentation { blocksPath in
                    guard let dataPath, let blocksPath else {
                        throw BitcoinKernelError.chainstateOptionsCreationFailed
                    }

                    guard let options = library.btck_chainstate_manager_options_create(
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
            defer { library.btck_chainstate_manager_options_destroy(chainstateOptions) }

            library.btck_chainstate_manager_options_set_worker_threads_num(chainstateOptions, 1)

            guard let chainstateManager = library.btck_chainstate_manager_create(chainstateOptions) else {
                if Self.isChainstateLocked(at: dataDirectory) {
                    throw BitcoinKernelError.chainstateLocked
                }
                throw BitcoinKernelError.chainstateCreationFailed
            }
            self.chainstateManager = chainstateManager

            let restoredTip = try currentTip()
            Self.logger.info("Kernel opened at persisted tip height \(restoredTip.height, privacy: .public)")
        } catch {
            Self.logger.error("Kernel initialization failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    deinit {
        library.btck_chainstate_manager_destroy(chainstateManager)
        library.btck_context_destroy(context)
        if let loggingConnection {
            library.btck_logging_connection_destroy(loggingConnection)
        }
    }

    func currentTip() throws -> ChainTip {
        guard let entry = library.btck_chainstate_manager_get_best_entry(chainstateManager) else {
            throw BitcoinKernelError.bestEntryUnavailable
        }

        let height = Int(library.btck_block_tree_entry_get_height(entry))
        guard let blockHash = library.btck_block_tree_entry_get_block_hash(entry) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        let bestHash = library.hexString(for: blockHash)

        guard let activeChain = library.btck_chainstate_manager_get_active_chain(chainstateManager) else {
            throw BitcoinKernelError.activeChainUnavailable
        }
        guard library.btck_chain_contains(activeChain, entry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("Best entry is not contained in the active chain.")
        }

        let activeChainHeight = Int(library.btck_chain_get_height(activeChain))
        guard activeChainHeight == height else {
            throw BitcoinKernelError.activeChainHeightMismatch(expected: height, actual: activeChainHeight)
        }

        guard let activeChainEntry = library.btck_chain_get_by_height(activeChain, Int32(height)) else {
            throw BitcoinKernelError.blockEntryUnavailable(height)
        }
        guard let activeChainHash = library.btck_block_tree_entry_get_block_hash(activeChainEntry) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        let activeChainTipHash = library.hexString(for: activeChainHash)
        guard activeChainTipHash == bestHash else {
            throw BitcoinKernelError.activeChainTipMismatch(expected: bestHash, actual: activeChainTipHash)
        }
        guard library.btck_block_tree_entry_equals(activeChainEntry, entry) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("Best entry and active-chain entry disagree at the tip height.")
        }

        guard let activeChainHeader = library.btck_block_tree_entry_get_block_header(activeChainEntry) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip header.")
        }
        defer { library.btck_block_header_destroy(activeChainHeader) }

        guard let copiedActiveChainHeader = library.btck_block_header_copy(activeChainHeader) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to copy the active-chain tip header.")
        }
        defer { library.btck_block_header_destroy(copiedActiveChainHeader) }

        guard let headerHash = library.btck_block_header_get_hash(copiedActiveChainHeader) else {
            throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip header hash.")
        }
        defer { library.btck_block_hash_destroy(headerHash) }

        guard library.btck_block_hash_equals(headerHash, activeChainHash) == 1 else {
            throw BitcoinKernelError.chainInspectionFailed("The active-chain tip header hash did not match the tip block hash.")
        }

        if height > 0 {
            guard let previousEntry = library.btck_block_tree_entry_get_previous(activeChainEntry) else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip did not expose a previous entry.")
            }
            guard Int(library.btck_block_tree_entry_get_height(previousEntry)) == height - 1 else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip previous entry had an unexpected height.")
            }
            guard let previousEntryHash = library.btck_block_tree_entry_get_block_hash(previousEntry) else {
                throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the previous active-chain entry hash.")
            }
            guard let previousHeaderHash = library.btck_block_header_get_prev_hash(copiedActiveChainHeader) else {
                throw BitcoinKernelError.chainInspectionFailed("Failed to retrieve the active-chain tip previous header hash.")
            }
            guard library.btck_block_hash_equals(previousHeaderHash, previousEntryHash) == 1 else {
                throw BitcoinKernelError.chainInspectionFailed("The active-chain tip header prev hash did not match the previous entry hash.")
            }
        }

        return ChainTip(height: height, hash: bestHash)
    }

    func interrupt() throws {
        let result = library.btck_context_interrupt(context)
        guard result == 0 else {
            throw BitcoinKernelError.contextInterruptFailed(result)
        }
    }

    func blockHeader(from rawBlock: Data, expectedHash: String? = nil) throws -> BlockHeader {
        guard rawBlock.count >= Self.serializedBlockHeaderLength else {
            throw BitcoinKernelError.blockTooShort(rawBlock.count)
        }

        let rawHeader = rawBlock.prefix(Self.serializedBlockHeaderLength)
        let header = try rawHeader.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let header = library.btck_block_header_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.blockHeaderCreationFailed
            }
            return header
        }
        defer { library.btck_block_header_destroy(header) }

        guard let blockHash = library.btck_block_header_get_hash(header) else {
            throw BitcoinKernelError.blockHeaderHashUnavailable
        }
        defer { library.btck_block_hash_destroy(blockHash) }

        let headerHash = library.hexString(for: blockHash)
        if let expectedHash, headerHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
            throw BitcoinKernelError.blockHeaderHashMismatch(expected: expectedHash, actual: headerHash)
        }

        guard let previousHash = library.btck_block_header_get_prev_hash(header) else {
            throw BitcoinKernelError.blockHashUnavailable
        }

        return BlockHeader(
            hash: headerHash,
            previousHash: library.hexString(for: previousHash),
            version: library.btck_block_header_get_version(header),
            timestamp: library.btck_block_header_get_timestamp(header),
            bits: library.btck_block_header_get_bits(header),
            nonce: library.btck_block_header_get_nonce(header)
        )
    }

    @discardableResult
    func process(rawBlock: Data, expectedHash: String? = nil) throws -> ChainTip {
        let header = try rawBlock.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let header = library.btck_block_header_create(baseAddress, Self.serializedBlockHeaderLength) else {
                throw BitcoinKernelError.blockHeaderCreationFailed
            }
            return header
        }
        defer { library.btck_block_header_destroy(header) }

        let headerSummary = try blockHeader(from: rawBlock, expectedHash: expectedHash)
        try process(header: header)
        _ = headerSummary

        let block = try rawBlock.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let block = library.btck_block_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.blockCreationFailed
            }
            return block
        }
        defer { library.btck_block_destroy(block) }

        let serializedBlock = try serializeBlock(block)
        guard serializedBlock == rawBlock else {
            throw BitcoinKernelError.blockSerializationMismatch
        }

        try inspectParsedBlock(block, against: header, expectedSummary: headerSummary)

        let secondTransaction = try extractSecondTransaction(from: block)
        defer {
            if let secondTransaction {
                library.btck_transaction_destroy(secondTransaction.transaction)
            }
        }

        var newBlock = Int32(0)
        let result = library.btck_chainstate_manager_process_block(chainstateManager, block, &newBlock)
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
        guard let validationState = library.btck_block_validation_state_create() else {
            throw BitcoinKernelError.blockHeaderProcessingFailed(-1)
        }
        defer { library.btck_block_validation_state_destroy(validationState) }

        let result = library.btck_chainstate_manager_process_block_header(chainstateManager, header, validationState)
        guard result == 0 else {
            throw BitcoinKernelError.blockHeaderProcessingFailed(result)
        }

        let validationMode = library.btck_block_validation_state_get_validation_mode(validationState)
        guard validationMode == kernelValidationModeValid else {
            let validationResult = library.btck_block_validation_state_get_block_validation_result(validationState)
            throw BitcoinKernelError.blockHeaderValidationFailed(mode: validationMode, result: validationResult)
        }
    }

    private func extractSecondTransaction(from block: OpaquePointer) throws -> (transaction: OpaquePointer, txid: String)? {
        let transactionCount = Int(library.btck_block_count_transactions(block))
        guard transactionCount > 1 else {
            return nil
        }

        guard let blockTransaction = library.btck_block_get_transaction_at(block, 1) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The block did not expose transaction 1.")
        }

        let inputCount = Int(library.btck_transaction_count_inputs(blockTransaction))
        guard inputCount > 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction has no inputs.")
        }

        let outputCount = Int(library.btck_transaction_count_outputs(blockTransaction))
        guard outputCount > 0 else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction has no outputs.")
        }

        guard library.btck_transaction_get_output_at(blockTransaction, 0) != nil else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("The second transaction did not expose output 0.")
        }

        let txid = try transactionID(for: blockTransaction)
        let serializedTransaction = try serializeTransaction(blockTransaction)
        let transaction = try serializedTransaction.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let transaction = library.btck_transaction_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.secondTransactionCreationFailed
            }
            return transaction
        }
        defer { library.btck_transaction_destroy(transaction) }

        guard let copiedTransaction = library.btck_transaction_copy(transaction) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the recreated second transaction.")
        }

        return (copiedTransaction, txid)
    }

    private func verifySecondTransaction(_ transaction: OpaquePointer, txid: String, in block: OpaquePointer) throws {
        guard let copiedTransaction = library.btck_transaction_copy(transaction) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the second transaction for verification.")
        }
        defer { library.btck_transaction_destroy(copiedTransaction) }

        guard let blockHash = library.btck_block_get_hash(block) else {
            throw BitcoinKernelError.blockHashUnavailable
        }
        defer { library.btck_block_hash_destroy(blockHash) }

        guard let blockEntry = library.btck_chainstate_manager_get_block_tree_entry_by_hash(chainstateManager, blockHash) else {
            throw BitcoinKernelError.processedBlockEntryUnavailable
        }

        guard let blockSpentOutputs = library.btck_block_spent_outputs_read(chainstateManager, blockEntry) else {
            throw BitcoinKernelError.processedBlockSpentOutputsUnavailable
        }
        defer { library.btck_block_spent_outputs_destroy(blockSpentOutputs) }

        guard let copiedBlockSpentOutputs = library.btck_block_spent_outputs_copy(blockSpentOutputs) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the processed block spent outputs.")
        }
        defer { library.btck_block_spent_outputs_destroy(copiedBlockSpentOutputs) }

        // This is a post-acceptance re-validation step. Block undo data excludes the coinbase
        // transaction, so transaction 1 maps to undo index 0. Tx1 is also a safe starting point:
        // a valid tx1 cannot spend the preceding coinbase, and without a public chainstate coin
        // lookup equivalent to CCoinsView::GetCoin we currently depend on undo data for prevouts.
        guard library.btck_block_spent_outputs_count(copiedBlockSpentOutputs) > 0,
              let transactionSpentOutputs = library.btck_block_spent_outputs_get_transaction_spent_outputs_at(copiedBlockSpentOutputs, 0) else {
            throw BitcoinKernelError.secondTransactionSpentOutputsUnavailable
        }
        guard let copiedTransactionSpentOutputs = library.btck_transaction_spent_outputs_copy(transactionSpentOutputs) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the second transaction spent outputs.")
        }
        defer { library.btck_transaction_spent_outputs_destroy(copiedTransactionSpentOutputs) }

        let inputCount = Int(library.btck_transaction_count_inputs(copiedTransaction))
        let spentOutputCount = Int(library.btck_transaction_spent_outputs_count(copiedTransactionSpentOutputs))
        guard spentOutputCount == inputCount else {
            throw BitcoinKernelError.secondTransactionSpentOutputsMismatch(expected: inputCount, actual: spentOutputCount)
        }

        var spentOutputs: [OpaquePointer?] = []
        spentOutputs.reserveCapacity(inputCount)
        defer {
            for spentOutput in spentOutputs {
                if let spentOutput {
                    library.btck_transaction_output_destroy(spentOutput)
                }
            }
        }

        for inputIndex in 0..<inputCount {
            guard let borrowedInput = library.btck_transaction_get_input_at(copiedTransaction, inputIndex) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing input \(inputIndex).")
            }
            guard let input = library.btck_transaction_input_copy(borrowedInput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy input \(inputIndex).")
            }
            defer { library.btck_transaction_input_destroy(input) }

            guard let borrowedOutPoint = library.btck_transaction_input_get_out_point(input) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing outpoint for input \(inputIndex).")
            }
            guard let outPoint = library.btck_transaction_out_point_copy(borrowedOutPoint) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the outpoint for input \(inputIndex).")
            }
            defer { library.btck_transaction_out_point_destroy(outPoint) }
            _ = library.btck_transaction_out_point_get_index(outPoint)
            guard let borrowedPreviousTxid = library.btck_transaction_out_point_get_txid(outPoint) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing prevout txid for input \(inputIndex).")
            }
            guard let previousTxid = library.btck_txid_copy(borrowedPreviousTxid) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the prevout txid for input \(inputIndex).")
            }
            defer { library.btck_txid_destroy(previousTxid) }
            guard library.btck_txid_equals(previousTxid, borrowedPreviousTxid) == 1 else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("The copied prevout txid for input \(inputIndex) did not match the original.")
            }
            _ = library.txidString(for: previousTxid)

            guard let borrowedCoin = library.btck_transaction_spent_outputs_get_coin_at(copiedTransactionSpentOutputs, inputIndex) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing spent coin for input \(inputIndex).")
            }
            guard let coin = library.btck_coin_copy(borrowedCoin) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent coin for input \(inputIndex).")
            }
            defer { library.btck_coin_destroy(coin) }
            _ = library.btck_coin_confirmation_height(coin)
            _ = library.btck_coin_is_coinbase(coin)

            guard let borrowedSpentOutput = library.btck_coin_get_output(coin) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing spent output for input \(inputIndex).")
            }
            guard let spentOutput = library.btck_transaction_output_copy(borrowedSpentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent output for input \(inputIndex).")
            }
            defer { library.btck_transaction_output_destroy(spentOutput) }

            guard let borrowedScriptPubkey = library.btck_transaction_output_get_script_pubkey(spentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing script pubkey for input \(inputIndex).")
            }
            guard let copiedScriptPubkey = library.btck_script_pubkey_copy(borrowedScriptPubkey) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy the spent script pubkey for input \(inputIndex).")
            }
            defer { library.btck_script_pubkey_destroy(copiedScriptPubkey) }

            let recreatedScriptPubkey = try recreateScriptPubkey(copiedScriptPubkey)
            defer { library.btck_script_pubkey_destroy(recreatedScriptPubkey) }

            let amount = library.btck_transaction_output_get_amount(spentOutput)
            guard let recreatedSpentOutput = library.btck_transaction_output_create(recreatedScriptPubkey, amount) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to reconstruct the spent output for input \(inputIndex).")
            }

            guard let reconstructedScriptPubkey = library.btck_transaction_output_get_script_pubkey(recreatedSpentOutput) else {
                library.btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing reconstructed script pubkey for input \(inputIndex).")
            }
            guard library.btck_transaction_output_get_amount(recreatedSpentOutput) == amount else {
                library.btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("The reconstructed spent output amount did not match for input \(inputIndex).")
            }

            let reconstructedScriptBytes = try serializeScriptPubkey(reconstructedScriptPubkey)
            let originalScriptBytes = try serializeScriptPubkey(copiedScriptPubkey)
            guard reconstructedScriptBytes == originalScriptBytes else {
                library.btck_transaction_output_destroy(recreatedSpentOutput)
                throw BitcoinKernelError.secondTransactionInspectionFailed("The reconstructed spent script pubkey bytes did not match for input \(inputIndex).")
            }

            spentOutputs.append(recreatedSpentOutput)
        }

        let precomputedTransactionData = spentOutputs.withUnsafeBufferPointer { spentOutputsBuffer in
            library.btck_precomputed_transaction_data_create(copiedTransaction, spentOutputsBuffer.baseAddress, spentOutputsBuffer.count)
        }
        guard let precomputedTransactionData else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to create precomputed transaction data.")
        }
        defer { library.btck_precomputed_transaction_data_destroy(precomputedTransactionData) }

        guard let copiedPrecomputedTransactionData = library.btck_precomputed_transaction_data_copy(precomputedTransactionData) else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to copy precomputed transaction data.")
        }
        defer { library.btck_precomputed_transaction_data_destroy(copiedPrecomputedTransactionData) }

        for inputIndex in 0..<spentOutputs.count {
            guard let spentOutput = spentOutputs[inputIndex],
                  let scriptPubkey = library.btck_transaction_output_get_script_pubkey(spentOutput) else {
                throw BitcoinKernelError.secondTransactionInspectionFailed("Missing script pubkey for input \(inputIndex).")
            }
            let amount = library.btck_transaction_output_get_amount(spentOutput)
            var status = kernelScriptVerifyStatusOK
            let verified = library.btck_script_pubkey_verify(
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
        guard let txid = library.btck_transaction_get_txid(transaction) else {
            throw BitcoinKernelError.secondTransactionTxidUnavailable
        }

        return library.txidString(for: txid)
    }

    private func serializeTransaction(_ transaction: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = library.btck_transaction_to_bytes(
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
        let result = library.btck_block_to_bytes(
            block,
            Self.kernelWriteBytesCallback,
            Unmanaged.passUnretained(collector).toOpaque()
        )

        guard result == 0, !collector.data.isEmpty else {
            throw BitcoinKernelError.blockSerializationFailed
        }

        return collector.data
    }

    private func recreateScriptPubkey(_ scriptPubkey: OpaquePointer) throws -> OpaquePointer {
        let serializedScriptPubkey = try serializeScriptPubkey(scriptPubkey)
        let recreatedScriptPubkey = serializedScriptPubkey.withUnsafeBytes { rawBuffer in
            library.btck_script_pubkey_create(rawBuffer.baseAddress, rawBuffer.count)
        }

        guard let recreatedScriptPubkey else {
            throw BitcoinKernelError.secondTransactionInspectionFailed("Failed to recreate spent script pubkey bytes.")
        }

        return recreatedScriptPubkey
    }

    private func serializeScriptPubkey(_ scriptPubkey: OpaquePointer) throws -> Data {
        let collector = KernelByteCollector()
        let result = library.btck_script_pubkey_to_bytes(
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
        guard let blockHeader = library.btck_block_get_header(block) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve the parsed block header.")
        }
        defer { library.btck_block_header_destroy(blockHeader) }

        guard let copiedBlockHeader = library.btck_block_header_copy(blockHeader) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the parsed block header.")
        }
        defer { library.btck_block_header_destroy(copiedBlockHeader) }

        guard let parsedHeaderHash = library.btck_block_header_get_hash(parsedHeader),
              let blockHeaderHash = library.btck_block_header_get_hash(copiedBlockHeader) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve parsed block header hashes.")
        }
        defer {
            library.btck_block_hash_destroy(parsedHeaderHash)
            library.btck_block_hash_destroy(blockHeaderHash)
        }

        guard library.btck_block_hash_equals(parsedHeaderHash, blockHeaderHash) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("The parsed block header hash did not match the block-derived header hash.")
        }

        guard library.btck_block_header_get_version(copiedBlockHeader) == expectedSummary.version,
              library.btck_block_header_get_timestamp(copiedBlockHeader) == expectedSummary.timestamp,
              library.btck_block_header_get_bits(copiedBlockHeader) == expectedSummary.bits,
              library.btck_block_header_get_nonce(copiedBlockHeader) == expectedSummary.nonce else {
            throw BitcoinKernelError.blockInspectionFailed("The block-derived header fields did not match the serialized header.")
        }
    }

    private func inspectProcessedBlock(_ block: OpaquePointer, rawBlock: Data) throws {
        guard let blockHash = library.btck_block_get_hash(block) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to retrieve the processed block hash.")
        }
        defer { library.btck_block_hash_destroy(blockHash) }

        guard let copiedBlockHash = library.btck_block_hash_copy(blockHash) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the processed block hash.")
        }
        defer { library.btck_block_hash_destroy(copiedBlockHash) }

        var blockHashBytes = [UInt8](repeating: 0, count: 32)
        library.btck_block_hash_to_bytes(copiedBlockHash, &blockHashBytes)
        guard let recreatedBlockHash = blockHashBytes.withUnsafeBufferPointer({
            library.btck_block_hash_create($0.baseAddress)
        }) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to recreate the processed block hash from bytes.")
        }
        defer { library.btck_block_hash_destroy(recreatedBlockHash) }

        guard library.btck_block_hash_equals(blockHash, copiedBlockHash) == 1,
              library.btck_block_hash_equals(blockHash, recreatedBlockHash) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("Processed block hash equality checks failed.")
        }

        guard let blockEntry = library.btck_chainstate_manager_get_block_tree_entry_by_hash(chainstateManager, recreatedBlockHash) else {
            throw BitcoinKernelError.processedBlockEntryUnavailable
        }

        guard let activeChain = library.btck_chainstate_manager_get_active_chain(chainstateManager) else {
            throw BitcoinKernelError.activeChainUnavailable
        }
        guard library.btck_chain_contains(activeChain, blockEntry) == 1 else {
            throw BitcoinKernelError.blockInspectionFailed("Processed block entry is not contained in the active chain.")
        }

        guard let readBlock = library.btck_block_read(chainstateManager, blockEntry) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to read the processed block back from disk.")
        }
        defer { library.btck_block_destroy(readBlock) }

        guard let copiedReadBlock = library.btck_block_copy(readBlock) else {
            throw BitcoinKernelError.blockInspectionFailed("Failed to copy the processed block read from disk.")
        }
        defer { library.btck_block_destroy(copiedReadBlock) }

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
}

private final class KernelByteCollector {
    var data = Data()
}

private final class LoadedBitcoinKernel {
    typealias ChainType = UInt8
    typealias LogCategory = UInt8
    typealias LogLevel = UInt8
    typealias LogCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void
    typealias WriteBytesCallback = @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?) -> Int32

    private let handle: UnsafeMutableRawPointer

    let btck_context_options_set_notifications_raw: UnsafeMutableRawPointer
    let btck_context_options_set_validation_interface_raw: UnsafeMutableRawPointer
    let btck_logging_set_level_category: @convention(c) (LogCategory, LogLevel) -> Void
    let btck_logging_enable_category: @convention(c) (LogCategory) -> Void
    let btck_logging_connection_create: @convention(c) (LogCallback?, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) -> OpaquePointer?
    let btck_logging_connection_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chain_parameters_create: @convention(c) (ChainType) -> OpaquePointer?
    let btck_chain_parameters_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_context_options_create: @convention(c) () -> OpaquePointer?
    let btck_context_options_set_chainparams: @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    let btck_context_options_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_context_create: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_context_interrupt: @convention(c) (OpaquePointer?) -> Int32
    let btck_context_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chainstate_manager_options_create: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int, UnsafePointer<CChar>?, Int) -> OpaquePointer?
    let btck_chainstate_manager_options_set_worker_threads_num: @convention(c) (OpaquePointer?, Int32) -> Void
    let btck_chainstate_manager_options_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chainstate_manager_create: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_chainstate_manager_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chainstate_manager_get_best_entry: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_chainstate_manager_get_active_chain: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_chain_get_height: @convention(c) (OpaquePointer?) -> Int32
    let btck_chain_get_by_height: @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    let btck_chain_contains: @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    let btck_block_tree_entry_get_previous: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_tree_entry_get_block_header: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_tree_entry_get_height: @convention(c) (OpaquePointer?) -> Int32
    let btck_block_tree_entry_get_block_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_tree_entry_equals: @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    let btck_block_header_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_block_header_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_get_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_get_prev_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_get_timestamp: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_get_bits: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_get_version: @convention(c) (OpaquePointer?) -> Int32
    let btck_block_header_get_nonce: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_block_validation_state_create: @convention(c) () -> OpaquePointer?
    let btck_block_validation_state_get_validation_mode: @convention(c) (OpaquePointer?) -> UInt8
    let btck_block_validation_state_get_block_validation_result: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_validation_state_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_block_read: @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    let btck_block_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_get_header: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_hash_create: @convention(c) (UnsafePointer<UInt8>?) -> OpaquePointer?
    let btck_block_hash_equals: @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    let btck_block_hash_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_hash_to_bytes: @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt8>?) -> Void
    let btck_block_hash_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_block_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_block_count_transactions: @convention(c) (OpaquePointer?) -> Int
    let btck_block_get_transaction_at: @convention(c) (OpaquePointer?, Int) -> OpaquePointer?
    let btck_block_get_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_to_bytes: @convention(c) (OpaquePointer?, WriteBytesCallback?, UnsafeMutableRawPointer?) -> Int32
    let btck_block_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_transaction_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_transaction_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_to_bytes: @convention(c) (OpaquePointer?, WriteBytesCallback?, UnsafeMutableRawPointer?) -> Int32
    let btck_transaction_count_outputs: @convention(c) (OpaquePointer?) -> Int
    let btck_transaction_get_output_at: @convention(c) (OpaquePointer?, Int) -> OpaquePointer?
    let btck_transaction_get_input_at: @convention(c) (OpaquePointer?, Int) -> OpaquePointer?
    let btck_transaction_count_inputs: @convention(c) (OpaquePointer?) -> Int
    let btck_transaction_get_txid: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_precomputed_transaction_data_create: @convention(c) (OpaquePointer?, UnsafePointer<OpaquePointer?>?, Int) -> OpaquePointer?
    let btck_precomputed_transaction_data_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_precomputed_transaction_data_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_script_pubkey_verify: @convention(c) (OpaquePointer?, Int64, OpaquePointer?, OpaquePointer?, UInt32, UInt32, UnsafeMutablePointer<UInt8>?) -> Int32
    let btck_script_pubkey_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_script_pubkey_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_script_pubkey_to_bytes: @convention(c) (OpaquePointer?, WriteBytesCallback?, UnsafeMutableRawPointer?) -> Int32
    let btck_script_pubkey_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_transaction_output_create: @convention(c) (OpaquePointer?, Int64) -> OpaquePointer?
    let btck_transaction_output_get_script_pubkey: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_output_get_amount: @convention(c) (OpaquePointer?) -> Int64
    let btck_transaction_output_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_output_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chainstate_manager_process_block_header: @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> Int32
    let btck_chainstate_manager_process_block: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<Int32>?) -> Int32
    let btck_chainstate_manager_get_block_tree_entry_by_hash: @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    let btck_block_spent_outputs_read: @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    let btck_block_spent_outputs_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_spent_outputs_count: @convention(c) (OpaquePointer?) -> Int
    let btck_block_spent_outputs_get_transaction_spent_outputs_at: @convention(c) (OpaquePointer?, Int) -> OpaquePointer?
    let btck_block_spent_outputs_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_transaction_spent_outputs_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_spent_outputs_count: @convention(c) (OpaquePointer?) -> Int
    let btck_transaction_spent_outputs_get_coin_at: @convention(c) (OpaquePointer?, Int) -> OpaquePointer?
    let btck_transaction_spent_outputs_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_transaction_input_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_input_get_out_point: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_input_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_transaction_out_point_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_out_point_get_index: @convention(c) (OpaquePointer?) -> UInt32
    let btck_transaction_out_point_get_txid: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_transaction_out_point_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_txid_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_txid_equals: @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    let btck_txid_to_bytes: @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt8>?) -> Void
    let btck_txid_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_coin_copy: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_coin_confirmation_height: @convention(c) (OpaquePointer?) -> UInt32
    let btck_coin_is_coinbase: @convention(c) (OpaquePointer?) -> Int32
    let btck_coin_get_output: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_coin_destroy: @convention(c) (OpaquePointer?) -> Void

    init() throws {
        let candidates = Self.candidateLibraryPaths()
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw BitcoinKernelError.libraryNotFound(candidates)
        }

        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let message = if let error = dlerror() {
                String(cString: error)
            } else {
                "unknown error"
            }
            throw BitcoinKernelError.libraryOpenFailed(message)
        }

        func loadSymbol<Function>(_ symbol: String) throws -> Function {
            guard let rawSymbol = dlsym(handle, symbol) else {
                throw BitcoinKernelError.symbolMissing(symbol)
            }
            return unsafeBitCast(rawSymbol, to: Function.self)
        }

        func loadRawSymbol(_ symbol: String) throws -> UnsafeMutableRawPointer {
            guard let rawSymbol = dlsym(handle, symbol) else {
                throw BitcoinKernelError.symbolMissing(symbol)
            }
            return rawSymbol
        }

        self.handle = handle
        btck_context_options_set_notifications_raw = try loadRawSymbol("btck_context_options_set_notifications")
        btck_context_options_set_validation_interface_raw = try loadRawSymbol("btck_context_options_set_validation_interface")
        btck_logging_set_level_category = try loadSymbol("btck_logging_set_level_category")
        btck_logging_enable_category = try loadSymbol("btck_logging_enable_category")
        btck_logging_connection_create = try loadSymbol("btck_logging_connection_create")
        btck_logging_connection_destroy = try loadSymbol("btck_logging_connection_destroy")
        btck_chain_parameters_create = try loadSymbol("btck_chain_parameters_create")
        btck_chain_parameters_destroy = try loadSymbol("btck_chain_parameters_destroy")
        btck_context_options_create = try loadSymbol("btck_context_options_create")
        btck_context_options_set_chainparams = try loadSymbol("btck_context_options_set_chainparams")
        btck_context_options_destroy = try loadSymbol("btck_context_options_destroy")
        btck_context_create = try loadSymbol("btck_context_create")
        btck_context_interrupt = try loadSymbol("btck_context_interrupt")
        btck_context_destroy = try loadSymbol("btck_context_destroy")
        btck_chainstate_manager_options_create = try loadSymbol("btck_chainstate_manager_options_create")
        btck_chainstate_manager_options_set_worker_threads_num = try loadSymbol("btck_chainstate_manager_options_set_worker_threads_num")
        btck_chainstate_manager_options_destroy = try loadSymbol("btck_chainstate_manager_options_destroy")
        btck_chainstate_manager_create = try loadSymbol("btck_chainstate_manager_create")
        btck_chainstate_manager_destroy = try loadSymbol("btck_chainstate_manager_destroy")
        btck_chainstate_manager_get_best_entry = try loadSymbol("btck_chainstate_manager_get_best_entry")
        btck_chainstate_manager_get_active_chain = try loadSymbol("btck_chainstate_manager_get_active_chain")
        btck_chain_get_height = try loadSymbol("btck_chain_get_height")
        btck_chain_get_by_height = try loadSymbol("btck_chain_get_by_height")
        btck_chain_contains = try loadSymbol("btck_chain_contains")
        btck_block_tree_entry_get_previous = try loadSymbol("btck_block_tree_entry_get_previous")
        btck_block_tree_entry_get_block_header = try loadSymbol("btck_block_tree_entry_get_block_header")
        btck_block_tree_entry_get_height = try loadSymbol("btck_block_tree_entry_get_height")
        btck_block_tree_entry_get_block_hash = try loadSymbol("btck_block_tree_entry_get_block_hash")
        btck_block_tree_entry_equals = try loadSymbol("btck_block_tree_entry_equals")
        btck_block_header_create = try loadSymbol("btck_block_header_create")
        btck_block_header_copy = try loadSymbol("btck_block_header_copy")
        btck_block_header_get_hash = try loadSymbol("btck_block_header_get_hash")
        btck_block_header_get_prev_hash = try loadSymbol("btck_block_header_get_prev_hash")
        btck_block_header_get_timestamp = try loadSymbol("btck_block_header_get_timestamp")
        btck_block_header_get_bits = try loadSymbol("btck_block_header_get_bits")
        btck_block_header_get_version = try loadSymbol("btck_block_header_get_version")
        btck_block_header_get_nonce = try loadSymbol("btck_block_header_get_nonce")
        btck_block_header_destroy = try loadSymbol("btck_block_header_destroy")
        btck_block_validation_state_create = try loadSymbol("btck_block_validation_state_create")
        btck_block_validation_state_get_validation_mode = try loadSymbol("btck_block_validation_state_get_validation_mode")
        btck_block_validation_state_get_block_validation_result = try loadSymbol("btck_block_validation_state_get_block_validation_result")
        btck_block_validation_state_destroy = try loadSymbol("btck_block_validation_state_destroy")
        btck_block_read = try loadSymbol("btck_block_read")
        btck_block_copy = try loadSymbol("btck_block_copy")
        btck_block_get_header = try loadSymbol("btck_block_get_header")
        btck_block_hash_create = try loadSymbol("btck_block_hash_create")
        btck_block_hash_equals = try loadSymbol("btck_block_hash_equals")
        btck_block_hash_copy = try loadSymbol("btck_block_hash_copy")
        btck_block_hash_to_bytes = try loadSymbol("btck_block_hash_to_bytes")
        btck_block_hash_destroy = try loadSymbol("btck_block_hash_destroy")
        btck_block_create = try loadSymbol("btck_block_create")
        btck_block_count_transactions = try loadSymbol("btck_block_count_transactions")
        btck_block_get_transaction_at = try loadSymbol("btck_block_get_transaction_at")
        btck_block_get_hash = try loadSymbol("btck_block_get_hash")
        btck_block_to_bytes = try loadSymbol("btck_block_to_bytes")
        btck_block_destroy = try loadSymbol("btck_block_destroy")
        btck_transaction_create = try loadSymbol("btck_transaction_create")
        btck_transaction_copy = try loadSymbol("btck_transaction_copy")
        btck_transaction_to_bytes = try loadSymbol("btck_transaction_to_bytes")
        btck_transaction_count_outputs = try loadSymbol("btck_transaction_count_outputs")
        btck_transaction_get_output_at = try loadSymbol("btck_transaction_get_output_at")
        btck_transaction_get_input_at = try loadSymbol("btck_transaction_get_input_at")
        btck_transaction_count_inputs = try loadSymbol("btck_transaction_count_inputs")
        btck_transaction_get_txid = try loadSymbol("btck_transaction_get_txid")
        btck_transaction_destroy = try loadSymbol("btck_transaction_destroy")
        btck_precomputed_transaction_data_create = try loadSymbol("btck_precomputed_transaction_data_create")
        btck_precomputed_transaction_data_copy = try loadSymbol("btck_precomputed_transaction_data_copy")
        btck_precomputed_transaction_data_destroy = try loadSymbol("btck_precomputed_transaction_data_destroy")
        btck_script_pubkey_verify = try loadSymbol("btck_script_pubkey_verify")
        btck_script_pubkey_copy = try loadSymbol("btck_script_pubkey_copy")
        btck_script_pubkey_create = try loadSymbol("btck_script_pubkey_create")
        btck_script_pubkey_to_bytes = try loadSymbol("btck_script_pubkey_to_bytes")
        btck_script_pubkey_destroy = try loadSymbol("btck_script_pubkey_destroy")
        btck_transaction_output_create = try loadSymbol("btck_transaction_output_create")
        btck_transaction_output_get_script_pubkey = try loadSymbol("btck_transaction_output_get_script_pubkey")
        btck_transaction_output_get_amount = try loadSymbol("btck_transaction_output_get_amount")
        btck_transaction_output_copy = try loadSymbol("btck_transaction_output_copy")
        btck_transaction_output_destroy = try loadSymbol("btck_transaction_output_destroy")
        btck_chainstate_manager_process_block_header = try loadSymbol("btck_chainstate_manager_process_block_header")
        btck_chainstate_manager_process_block = try loadSymbol("btck_chainstate_manager_process_block")
        btck_chainstate_manager_get_block_tree_entry_by_hash = try loadSymbol("btck_chainstate_manager_get_block_tree_entry_by_hash")
        btck_block_spent_outputs_read = try loadSymbol("btck_block_spent_outputs_read")
        btck_block_spent_outputs_copy = try loadSymbol("btck_block_spent_outputs_copy")
        btck_block_spent_outputs_count = try loadSymbol("btck_block_spent_outputs_count")
        btck_block_spent_outputs_get_transaction_spent_outputs_at = try loadSymbol("btck_block_spent_outputs_get_transaction_spent_outputs_at")
        btck_block_spent_outputs_destroy = try loadSymbol("btck_block_spent_outputs_destroy")
        btck_transaction_spent_outputs_copy = try loadSymbol("btck_transaction_spent_outputs_copy")
        btck_transaction_spent_outputs_count = try loadSymbol("btck_transaction_spent_outputs_count")
        btck_transaction_spent_outputs_get_coin_at = try loadSymbol("btck_transaction_spent_outputs_get_coin_at")
        btck_transaction_spent_outputs_destroy = try loadSymbol("btck_transaction_spent_outputs_destroy")
        btck_transaction_input_copy = try loadSymbol("btck_transaction_input_copy")
        btck_transaction_input_get_out_point = try loadSymbol("btck_transaction_input_get_out_point")
        btck_transaction_input_destroy = try loadSymbol("btck_transaction_input_destroy")
        btck_transaction_out_point_copy = try loadSymbol("btck_transaction_out_point_copy")
        btck_transaction_out_point_get_index = try loadSymbol("btck_transaction_out_point_get_index")
        btck_transaction_out_point_get_txid = try loadSymbol("btck_transaction_out_point_get_txid")
        btck_transaction_out_point_destroy = try loadSymbol("btck_transaction_out_point_destroy")
        btck_txid_copy = try loadSymbol("btck_txid_copy")
        btck_txid_equals = try loadSymbol("btck_txid_equals")
        btck_txid_to_bytes = try loadSymbol("btck_txid_to_bytes")
        btck_txid_destroy = try loadSymbol("btck_txid_destroy")
        btck_coin_copy = try loadSymbol("btck_coin_copy")
        btck_coin_confirmation_height = try loadSymbol("btck_coin_confirmation_height")
        btck_coin_is_coinbase = try loadSymbol("btck_coin_is_coinbase")
        btck_coin_get_output = try loadSymbol("btck_coin_get_output")
        btck_coin_destroy = try loadSymbol("btck_coin_destroy")
    }

    deinit {
        dlclose(handle)
    }

    func makeChainParameters() throws -> OpaquePointer {
        guard let chainParameters = btck_chain_parameters_create(3) else {
            throw BitcoinKernelError.chainParametersCreationFailed
        }
        return chainParameters
    }

    func makeLoggingConnection(logCallback: @escaping LogCallback) -> OpaquePointer? {
        btck_logging_set_level_category(kernelLogCategoryAll, kernelLogLevelInfo)
        btck_logging_enable_category(kernelLogCategoryAll)
        return btck_logging_connection_create(logCallback, nil, nil)
    }

    func setNotifications(_ contextOptions: OpaquePointer, sink: KernelNotificationSink) {
        let retainedSink = Unmanaged.passRetained(sink)
        let callbacks = btck_NotificationInterfaceCallbacks(
            user_data: retainedSink.toOpaque(),
            user_data_destroy: BitcoinKernel.kernelNotificationDestroyCallback,
            // Keep these callbacks wired so the C API path stays exercised, but rely on the
            // kernel's own log lines for the user-visible signal to avoid redundant noise.
            block_tip: BitcoinKernel.kernelBlockTipCallback,
            header_tip: BitcoinKernel.kernelHeaderTipCallback,
            progress: BitcoinKernel.kernelProgressCallback,
            warning_set: BitcoinKernel.kernelWarningSetCallback,
            warning_unset: BitcoinKernel.kernelWarningUnsetCallback,
            flush_error: BitcoinKernel.kernelFlushErrorCallback,
            fatal_error: BitcoinKernel.kernelFatalErrorCallback
        )

        btck_call_context_options_set_notifications(
            btck_context_options_set_notifications_raw,
            UnsafeMutableRawPointer(contextOptions),
            callbacks
        )
    }

    func setValidationInterface(_ contextOptions: OpaquePointer, sink: KernelValidationSink) {
        let retainedSink = Unmanaged.passRetained(sink)
        var callbacks = btck_ValidationInterfaceCallbacks()
        callbacks.user_data = retainedSink.toOpaque()
        callbacks.user_data_destroy = BitcoinKernel.kernelValidationDestroyCallback
        callbacks.block_checked = BitcoinKernel.kernelBlockCheckedCallback
        callbacks.pow_valid_block = BitcoinKernel.kernelPoWValidBlockCallback
        callbacks.block_connected = BitcoinKernel.kernelBlockConnectedCallback
        callbacks.block_disconnected = BitcoinKernel.kernelBlockDisconnectedCallback

        // As with notifications, Swift's dlsym-based C interop is awkward for a by-value callback struct,
        // so a tiny C shim performs the ABI-sensitive call.
        btck_call_context_options_set_validation_interface(
            btck_context_options_set_validation_interface_raw,
            UnsafeMutableRawPointer(contextOptions),
            callbacks
        )
    }

    func makeContextOptions() throws -> OpaquePointer {
        guard let contextOptions = btck_context_options_create() else {
            throw BitcoinKernelError.contextOptionsCreationFailed
        }
        return contextOptions
    }

    func hexString(for blockHash: OpaquePointer) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        btck_block_hash_to_bytes(blockHash, &bytes)
        return bytes.reversed().map { String(format: "%02x", $0) }.joined()
    }

    func txidString(for txid: OpaquePointer) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        btck_txid_to_bytes(txid, &bytes)
        return bytes.reversed().map { String(format: "%02x", $0) }.joined()
    }

    private static func candidateLibraryPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        var paths: [String] = []

        if let explicitPath = environment["BTCK_LIB_PATH"], !explicitPath.isEmpty {
            paths.append(explicitPath)
        }

        if let bundleFramework = Bundle.main.privateFrameworksPath {
            paths.append((bundleFramework as NSString).appendingPathComponent("libbitcoinkernel.dylib"))
        }

        paths.append(contentsOf: [
            "/opt/homebrew/lib/libbitcoinkernel.dylib",
            "/usr/local/lib/libbitcoinkernel.dylib"
        ])

        return paths
    }
}

private final class KernelNotificationSink {
    private let library: LoadedBitcoinKernel

    init(library: LoadedBitcoinKernel) {
        self.library = library
    }

    func observeBlockTip(state: UInt8, entry: UnsafeRawPointer?, verificationProgress: Double) {
        guard let entry else {
            return
        }

        let opaqueEntry = OpaquePointer(entry)
        // Keep this notification path exercised, but silence it because the kernel's UpdateTip
        // log line already provides a better user-visible tip update message.
        _ = library.btck_block_tree_entry_get_height(opaqueEntry)
        _ = library.btck_block_tree_entry_get_block_hash(opaqueEntry).map(library.hexString(for:))
        _ = state
        _ = verificationProgress
    }

    func observeWarningUnset(warning: UInt8) {
        // Keep this callback wired for coverage, but silence "cleared" messages because they are
        // mostly state resets and add noise without actionable information.
        _ = warningDescription(warning)
    }

    func logHeaderTip(state: UInt8, height: Int64, timestamp: Int64, presync: Bool) {
        BitcoinKernel.logger.info(
            "Kernel header tip height \(height, privacy: .public) state \(self.synchronizationStateDescription(state), privacy: .public) timestamp \(timestamp, privacy: .public) presync \(presync, privacy: .public)"
        )
    }

    func logProgress(title: String, progressPercent: Int32, resumePossible: Bool) {
        BitcoinKernel.logger.info(
            "Kernel progress \(title, privacy: .public) \(progressPercent, privacy: .public)% resumePossible \(resumePossible, privacy: .public)"
        )
    }

    func logWarningSet(warning: UInt8, message: String) {
        BitcoinKernel.logger.warning(
            "Kernel warning \(self.warningDescription(warning), privacy: .public): \(message, privacy: .public)"
        )
    }

    func logFlushError(message: String) {
        BitcoinKernel.logger.error("Kernel flush error: \(message, privacy: .public)")
    }

    func logFatalError(message: String) {
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
    private let library: LoadedBitcoinKernel

    init(library: LoadedBitcoinKernel) {
        self.library = library
    }

    func logBlockChecked(block: UnsafeMutableRawPointer?, state: UnsafeRawPointer?) {
        guard
            let block = block.map(OpaquePointer.init),
            let state = state.map(OpaquePointer.init)
        else {
            return
        }

        let blockHash = blockHashString(for: block) ?? "unavailable"
        let validationMode = library.btck_block_validation_state_get_validation_mode(state)
        let validationResult = library.btck_block_validation_state_get_block_validation_result(state)

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

    func logPoWValidBlock(block: UnsafeMutableRawPointer?, entry: UnsafeRawPointer?) {
        logBlockLifecycleEvent(prefix: "Kernel pow-valid block", block: block, entry: entry)
    }

    func logBlockConnected(block: UnsafeMutableRawPointer?, entry: UnsafeRawPointer?) {
        logBlockLifecycleEvent(prefix: "Kernel block connected", block: block, entry: entry)
    }

    func logBlockDisconnected(block: UnsafeMutableRawPointer?, entry: UnsafeRawPointer?) {
        logBlockLifecycleEvent(prefix: "Kernel block disconnected", block: block, entry: entry)
    }

    private func logBlockLifecycleEvent(prefix: String, block: UnsafeMutableRawPointer?, entry: UnsafeRawPointer?) {
        let blockHash = block.map(OpaquePointer.init).flatMap(blockHashString(for:)) ?? "unavailable"
        let (entryHeight, entryHash) = entryInfo(entry)
        BitcoinKernel.logger.info(
            "\(prefix, privacy: .public) hash \(blockHash, privacy: .public) entryHeight \(entryHeight, privacy: .public) entryHash \(entryHash, privacy: .public)"
        )
    }

    private func blockHashString(for block: OpaquePointer) -> String? {
        guard let blockHash = library.btck_block_get_hash(block) else {
            return nil
        }
        defer { library.btck_block_hash_destroy(blockHash) }
        return library.hexString(for: blockHash)
    }

    private func entryInfo(_ entry: UnsafeRawPointer?) -> (Int, String) {
        guard let entry else {
            return (-1, "unavailable")
        }

        let opaqueEntry = OpaquePointer(entry)
        let height = Int(library.btck_block_tree_entry_get_height(opaqueEntry))
        let blockHash = library.btck_block_tree_entry_get_block_hash(opaqueEntry).map(library.hexString(for:)) ?? "unavailable"
        return (height, blockHash)
    }

    private func validationResultDescription(_ result: UInt32) -> String {
        switch result {
        case 0:
            return "unset"
        case 1:
            return "consensus"
        case 2:
            return "cached_invalid"
        case 3:
            return "invalid_header"
        case 4:
            return "mutated"
        case 5:
            return "missing_prev"
        case 6:
            return "invalid_prev"
        case 7:
            return "time_future"
        case 8:
            return "header_low_work"
        default:
            return "unknown(\(result))"
        }
    }
}
