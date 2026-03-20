import Darwin
import Foundation
import OSLog

private let kernelLogCategoryAll: UInt8 = 0
private let kernelLogLevelInfo: UInt8 = 2

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
    case blockCreationFailed
    case blockProcessingFailed(Int32)
    case activeChainUnavailable
    case bestEntryUnavailable
    case blockEntryUnavailable(Int)
    case blockHashUnavailable

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
        case .blockCreationFailed:
            return "Failed to parse raw block bytes."
        case .blockProcessingFailed(let code):
            return "Kernel block processing failed with code \(code)."
        case .activeChainUnavailable:
            return "Kernel did not expose an active chain."
        case .bestEntryUnavailable:
            return "Kernel did not expose a best block entry."
        case .blockEntryUnavailable(let height):
            return "No active-chain entry exists at height \(height)."
        case .blockHashUnavailable:
            return "Failed to read block hash from kernel state."
        }
    }
}

final class BitcoinKernel {
    private static let logger = Logger(subsystem: "nl.sprovoost.Node", category: "BitcoinKernel")
    private static let serializedBlockHeaderLength = 80
    private static let kernelLogCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void = { _, message, messageLength in
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

        return ChainTip(height: height, hash: library.hexString(for: blockHash))
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
        _ = try blockHeader(from: rawBlock, expectedHash: expectedHash)

        let block = try rawBlock.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let block = library.btck_block_create(baseAddress, rawBuffer.count) else {
                throw BitcoinKernelError.blockCreationFailed
            }
            return block
        }
        defer { library.btck_block_destroy(block) }

        var newBlock = Int32(0)
        let result = library.btck_chainstate_manager_process_block(chainstateManager, block, &newBlock)
        guard result == 0 else {
            throw BitcoinKernelError.blockProcessingFailed(result)
        }

        return try currentTip()
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
}

private final class LoadedBitcoinKernel {
    typealias ChainType = UInt8
    typealias LogCategory = UInt8
    typealias LogLevel = UInt8
    typealias LogCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void

    private let handle: UnsafeMutableRawPointer

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
    let btck_block_tree_entry_get_height: @convention(c) (OpaquePointer?) -> Int32
    let btck_block_tree_entry_get_block_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_block_header_get_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_get_prev_hash: @convention(c) (OpaquePointer?) -> OpaquePointer?
    let btck_block_header_get_timestamp: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_get_bits: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_get_version: @convention(c) (OpaquePointer?) -> Int32
    let btck_block_header_get_nonce: @convention(c) (OpaquePointer?) -> UInt32
    let btck_block_header_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_block_hash_to_bytes: @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt8>?) -> Void
    let btck_block_hash_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_block_create: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    let btck_block_destroy: @convention(c) (OpaquePointer?) -> Void
    let btck_chainstate_manager_process_block: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<Int32>?) -> Int32

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

        self.handle = handle
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
        btck_block_tree_entry_get_height = try loadSymbol("btck_block_tree_entry_get_height")
        btck_block_tree_entry_get_block_hash = try loadSymbol("btck_block_tree_entry_get_block_hash")
        btck_block_header_create = try loadSymbol("btck_block_header_create")
        btck_block_header_get_hash = try loadSymbol("btck_block_header_get_hash")
        btck_block_header_get_prev_hash = try loadSymbol("btck_block_header_get_prev_hash")
        btck_block_header_get_timestamp = try loadSymbol("btck_block_header_get_timestamp")
        btck_block_header_get_bits = try loadSymbol("btck_block_header_get_bits")
        btck_block_header_get_version = try loadSymbol("btck_block_header_get_version")
        btck_block_header_get_nonce = try loadSymbol("btck_block_header_get_nonce")
        btck_block_header_destroy = try loadSymbol("btck_block_header_destroy")
        btck_block_hash_to_bytes = try loadSymbol("btck_block_hash_to_bytes")
        btck_block_hash_destroy = try loadSymbol("btck_block_hash_destroy")
        btck_block_create = try loadSymbol("btck_block_create")
        btck_block_destroy = try loadSymbol("btck_block_destroy")
        btck_chainstate_manager_process_block = try loadSymbol("btck_chainstate_manager_process_block")
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
