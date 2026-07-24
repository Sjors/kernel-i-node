//
//  NodeTests.swift
//  NodeTests
//
//  Created by Sjors Provoost on 14/03/2026.
//

import Foundation
import Testing
@testable import Node

private final class TestByteCollector {
    var data = Data()
}

private let testWriteBytesCallback: @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?) -> Int32 = { bytes, size, userData in
    guard let userData else {
        return 1
    }
    let collector = Unmanaged<TestByteCollector>.fromOpaque(userData).takeUnretainedValue()
    if let bytes, size > 0 {
        collector.data.append(contentsOf: UnsafeRawBufferPointer(start: bytes, count: size))
    }
    return 0
}

struct NodeTests {
    @Test func syncSnapshotProgressFractionUsesRemoteHeight() async throws {
        let snapshot = SyncSnapshot(
            phase: .syncing,
            statusText: "Syncing",
            localHeight: 75,
            remoteHeight: 100,
            tipHash: ""
        )

        #expect(snapshot.progressFraction == 0.75)
    }

    @Test func defaultStorageRootEndsInKernelSignet() async throws {
        let path = NodeSyncEngine.defaultStorageRoot().path(percentEncoded: false)
        #expect(path.contains("/Node/kernel-signet"))
    }

    @Test func nodeViewModelDoesNotAutoStartInPreviewOrTestHosts() async throws {
        #expect(NodeViewModel.shouldAutoStart(environment: [:]))
        #expect(!NodeViewModel.shouldAutoStart(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        #expect(!NodeViewModel.shouldAutoStart(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]))
    }

    /// The default signet challenge from Bitcoin Core's chainparams.cpp. Passing it through the
    /// custom-signet path must accept the same chain as the built-in signet parameters.
    static let defaultSignetChallengeHex =
        "512103ad5e0edad18cb1f0fc0d28a3d4f1f3e445640337489abb10404f2d1e086be430210359ef5021964fe22d6f8e05b2463c9540ce96883fe3b278760f048f5189f2e6c452ae"

    @Test func signetSettingsDefaultToStandardSignet() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)

        let snapshot = try SignetSettings.snapshot(defaults)
        #expect(snapshot.challenge == nil)
        #expect(snapshot.apiBaseURL == SignetSettings.defaultAPIBaseURL)
    }

    @Test func signetSettingsParseCustomChallengeAndURL() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        defaults.set(" 51 ", forKey: SignetSettings.challengeKey)
        defaults.set("https://example.com/signet/api", forKey: SignetSettings.apiURLKey)

        let snapshot = try SignetSettings.snapshot(defaults)
        #expect(snapshot.challenge == Data([0x51]))
        #expect(snapshot.apiBaseURL == URL(string: "https://example.com/signet/api"))
    }

    @Test func signetSettingsRejectInvalidChallengeHex() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        defaults.set("zz", forKey: SignetSettings.challengeKey)

        #expect(throws: SignetSettingsError.self) {
            try SignetSettings.snapshot(defaults)
        }

        defaults.set("512", forKey: SignetSettings.challengeKey)
        #expect(throws: SignetSettingsError.self) {
            try SignetSettings.snapshot(defaults)
        }
    }

    @Test func signetSettingsRejectInvalidAPIURL() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        defaults.set("ftp://example.com", forKey: SignetSettings.apiURLKey)

        #expect(throws: SignetSettingsError.self) {
            try SignetSettings.snapshot(defaults)
        }
    }

    @Test func customChallengeUsesDistinctStorageRoot() async throws {
        let custom = SignetSettingsSnapshot(
            challenge: SignetSettings.data(fromHex: Self.defaultSignetChallengeHex),
            apiBaseURL: SignetSettings.defaultAPIBaseURL
        )
        let defaultSnapshot = SignetSettingsSnapshot(challenge: nil, apiBaseURL: SignetSettings.defaultAPIBaseURL)

        let customRoot = NodeSyncEngine.storageRoot(for: custom)
        #expect(customRoot != NodeSyncEngine.defaultStorageRoot())
        #expect(customRoot.lastPathComponent.hasPrefix("kernel-signet-"))
        #expect(NodeSyncEngine.storageRoot(for: defaultSnapshot) == NodeSyncEngine.defaultStorageRoot())
        // Deterministic: the same challenge always maps to the same directory.
        #expect(NodeSyncEngine.storageRoot(for: custom) == customRoot)
    }

    @Test func transactionCheckAcceptsGenesisCoinbaseAndRejectsOutputlessTransaction() async throws {
        // The genesis coinbase transaction (shared by all networks, including signet).
        let genesisCoinbaseHex =
            "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d010445" +
            "5468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e" +
            "64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7" +
            "105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac" +
            "00000000"
        let validBytes = try #require(SignetSettings.data(fromHex: genesisCoinbaseHex))
        let validTransaction = try #require(validBytes.withUnsafeBytes {
            btck_transaction_create($0.baseAddress, $0.count)
        })
        defer { btck_transaction_destroy(validTransaction) }

        let validState = try #require(btck_tx_validation_state_create())
        defer { btck_tx_validation_state_destroy(validState) }
        #expect(btck_transaction_check(validTransaction, validState) == 1)
        #expect(
            btck_tx_validation_state_get_validation_mode(validState) ==
            btck_swift_btck_ValidationMode_VALID()
        )
        #expect(
            btck_tx_validation_state_get_tx_validation_result(validState) ==
            btck_swift_btck_TxValidationResult_UNSET()
        )

        // One input, no outputs: parses fine but violates consensus (bad-txns-vout-empty).
        let outputlessHex =
            "0200000001" + String(repeating: "0", count: 64) + "00000000" + "00" + "ffffffff" + "00" + "00000000"
        let invalidBytes = try #require(SignetSettings.data(fromHex: outputlessHex))
        let invalidTransaction = try #require(invalidBytes.withUnsafeBytes {
            btck_transaction_create($0.baseAddress, $0.count)
        })
        defer { btck_transaction_destroy(invalidTransaction) }

        let invalidState = try #require(btck_tx_validation_state_create())
        defer { btck_tx_validation_state_destroy(invalidState) }
        #expect(btck_transaction_check(invalidTransaction, invalidState) == 0)
        #expect(
            btck_tx_validation_state_get_validation_mode(invalidState) ==
            btck_swift_btck_ValidationMode_INVALID()
        )
        #expect(
            btck_tx_validation_state_get_tx_validation_result(invalidState) ==
            btck_swift_btck_TxValidationResult_CONSENSUS()
        )
    }

    @Test func transactionIntrospectionExposesLocktimeSequenceScriptSigAndWitness() async throws {
        // Hand-crafted segwit transaction: one input (empty scriptSig, sequence fffffffe,
        // witness items [aa, beef]), one OP_TRUE output, locktime 0x01020304.
        let rawTransactionHex =
            "02000000" + "0001" +
            "01" + String(repeating: "11", count: 32) + "00000000" + "00" + "feffffff" +
            "01" + "0000000000000000" + "01" + "51" +
            "02" + "01aa" + "02beef" +
            "04030201"
        let rawTransaction = try #require(SignetSettings.data(fromHex: rawTransactionHex))
        let transaction = try #require(rawTransaction.withUnsafeBytes {
            btck_transaction_create($0.baseAddress, $0.count)
        })
        defer { btck_transaction_destroy(transaction) }

        #expect(btck_transaction_get_locktime(transaction) == 0x01020304)

        let input = try #require(btck_transaction_get_input_at(transaction, 0))
        #expect(btck_transaction_input_get_sequence(input) == 0xfffffffe)

        let scriptSigCollector = TestByteCollector()
        #expect(btck_transaction_input_get_script_sig(
            input, testWriteBytesCallback, Unmanaged.passUnretained(scriptSigCollector).toOpaque()
        ) == 0)
        #expect(scriptSigCollector.data.isEmpty)

        let witnessStack = try #require(btck_transaction_input_get_witness_stack(input))
        let copiedWitnessStack = try #require(btck_witness_stack_copy(witnessStack))
        defer { btck_witness_stack_destroy(copiedWitnessStack) }
        #expect(btck_witness_stack_count_items(copiedWitnessStack) == 2)

        let expectedItems: [Data] = [Data([0xaa]), Data([0xbe, 0xef])]
        for (index, expectedItem) in expectedItems.enumerated() {
            let collector = TestByteCollector()
            #expect(btck_witness_stack_get_item_at(
                copiedWitnessStack, index, testWriteBytesCallback, Unmanaged.passUnretained(collector).toOpaque()
            ) == 0)
            #expect(collector.data == expectedItem)
        }
    }

    @Test func blockHeaderParsingRoundTripsAndExposesFields() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let kernel = try BitcoinKernel(storageRoot: tmp, inMemory: true)

        // Crafted 80-byte header with known little-endian field values. The previous
        // hash uses distinct ascending bytes so a byte-order mistake cannot go unnoticed.
        let prevHashSerializedHex = (0..<32).map { String(format: "%02x", $0) }.joined()
        let rawHeaderHex =
            "20000000" +
            prevHashSerializedHex +
            String(repeating: "bb", count: 32) +
            "78563412" +
            "ae77031e" +
            "efbeadde"
        let rawHeader = try #require(SignetSettings.data(fromHex: rawHeaderHex))

        // blockHeader(from:) internally serializes the parsed header back through
        // btck_block_header_to_bytes and requires an exact byte match.
        let header = try kernel.blockHeader(from: rawHeader)
        #expect(header.version == 0x20)
        #expect(header.timestamp == 0x12345678)
        #expect(header.bits == 0x1e0377ae)
        #expect(header.nonce == 0xdeadbeef)
        // Hashes display in reverse byte order relative to their serialization.
        let prevHashDisplayHex = (0..<32).reversed().map { String(format: "%02x", $0) }.joined()
        #expect(header.previousHash == prevHashDisplayHex)
    }

    @Test func inMemoryKernelWithDefaultChallengeMatchesDefaultSignetGenesis() async throws {
        let challenge = try #require(SignetSettings.data(fromHex: Self.defaultSignetChallengeHex))

        let defaultTmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: defaultTmp) }
        let defaultKernel = try BitcoinKernel(storageRoot: defaultTmp, inMemory: true)
        let defaultTip = try defaultKernel.currentTip()

        let customTmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: customTmp) }
        let customKernel = try BitcoinKernel(storageRoot: customTmp, signetChallenge: challenge, inMemory: true)
        let customTip = try customKernel.currentTip()

        #expect(customTip.height == 0)
        #expect(customTip.hash == defaultTip.hash)
    }

    @Test func chainstateLockedErrorHasHelpfulDescription() async throws {
        #expect(BitcoinKernelError.chainstateLocked.errorDescription == "The chainstate is already in use by another Node instance.")
    }

    @Test func blockHeaderHashMismatchErrorHasHelpfulDescription() async throws {
        #expect(
            BitcoinKernelError.blockHeaderHashMismatch(expected: "expected-hash", actual: "actual-hash").errorDescription
            == "Block header hash mismatch. Expected expected-hash, got actual-hash."
        )
    }

    @Test func secondTransactionVerificationErrorHasHelpfulDescription() async throws {
        #expect(
            BitcoinKernelError.secondTransactionVerificationFailed(txid: "txid", inputIndex: 1, status: 2).errorDescription
            == "Second transaction verification failed for txid txid at input 1 with status 2."
        )
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsDefaultSnapshotDisablesNamedCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled)
        #expect(snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsMasterToggleDisablesAllCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.loggingEnabledKey)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(!snapshot.isEnabled)
        #expect(!snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsInternalLogsTogglePreservesCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.internalLogsEnabledKey)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled)
        #expect(!snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsCategoryToggleRemovesOnlyThatCategory() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)

        let validationCategory = try #require(
            KernelLogSettings.categories.first(where: { $0.id == "validation" })
        )
        defaults.set(true, forKey: validationCategory.preferenceKey)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled)
        #expect(snapshot.enabledCategories.contains(validationCategory.kernelCategory))
        #expect(snapshot.enabledCategories.count == 1)
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsCategoryHelperTracksValidationToggle() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)

        #expect(!KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryValidation, defaults: defaults))

        let validationCategory = try #require(
            KernelLogSettings.categories.first(where: { $0.id == "validation" })
        )
        defaults.set(true, forKey: validationCategory.preferenceKey)

        #expect(KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryValidation, defaults: defaults))
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsCategoryHelperRespectsMasterToggle() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.loggingEnabledKey)

        #expect(!KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryValidation, defaults: defaults))
        #expect(!KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryKernel, defaults: defaults))
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsParsesTaggedRawLogCategories() async throws {
        #expect(KernelLogSettings.categoryForRawLogLine("[validation] Enqueuing BlockConnected:") == KernelLogSettings.kernelLogCategoryValidation)
        #expect(KernelLogSettings.categoryForRawLogLine("[kernel] something happened") == KernelLogSettings.kernelLogCategoryKernel)
        #expect(
            KernelLogSettings.categoryForRawLogLine("2026-03-20T21:24:29Z [validation] Enqueuing BlockConnected:")
            == KernelLogSettings.kernelLogCategoryValidation
        )
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func kernelLogSettingsLeavesUntaggedRawLogLinesAlone() async throws {
        #expect(KernelLogSettings.categoryForRawLogLine("UpdateTip: new best=...") == nil)
        #expect(KernelLogSettings.categoryForRawLogLine("[unknown] something") == nil)
        #expect(KernelLogSettings.categoryForRawLogLine("2026-03-20T21:24:29Z UpdateTip: new best=...") == nil)
    }

    @Test(.enabled(if: KernelLogSettings.isLoggingAvailable))
    func iOSSettingsBundleDefaultsMatchKernelLogSettingsDefaults() async throws {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let rootPlistURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Node/Settings.bundle/Root.plist")
        let data = try Data(contentsOf: rootPlistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        let specifiers = try #require(plist["PreferenceSpecifiers"] as? [[String: Any]])

        let defaultsByKey = Dictionary(uniqueKeysWithValues: specifiers.compactMap { specifier -> (String, Bool)? in
            guard
                let key = specifier["Key"] as? String,
                let value = specifier["DefaultValue"] as? Bool
            else {
                return nil
            }
            return (key, value)
        })

        #expect(defaultsByKey[KernelLogSettings.loggingEnabledKey] == true)
        #expect(defaultsByKey[KernelLogSettings.internalLogsEnabledKey] == true)

        for category in KernelLogSettings.categories {
            #expect(defaultsByKey[category.preferenceKey] == false)
        }

        #expect(defaultsByKey[KernelLogSettings.logTimestampsKey] == false)
        #expect(defaultsByKey[KernelLogSettings.logTimeMicrosKey] == false)
        #expect(defaultsByKey[KernelLogSettings.logThreadNamesKey] == false)
        #expect(defaultsByKey[KernelLogSettings.logSourceLocationsKey] == false)
        #expect(defaultsByKey[KernelLogSettings.alwaysPrintCategoryLevelsKey] == false)
    }

    @Test func disabledIOSSettingsBundleContainsNoToggleSpecifiers() async throws {
        guard !KernelLogSettings.isLoggingAvailable else {
            return
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let rootPlistURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Node/Settings.bundle/Root.LoggingDisabled.plist")
        let data = try Data(contentsOf: rootPlistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        let specifiers = try #require(plist["PreferenceSpecifiers"] as? [[String: Any]])

        #expect(specifiers.allSatisfy { ($0["Type"] as? String) != "PSToggleSwitchSpecifier" })
        #expect(specifiers.contains { ($0["FooterText"] as? String) == "Kernel logging settings are disabled in this build." })

        // The custom signet text fields remain available in logging-disabled builds.
        let textFieldKeys = specifiers
            .filter { ($0["Type"] as? String) == "PSTextFieldSpecifier" }
            .compactMap { $0["Key"] as? String }
        #expect(textFieldKeys == [SignetSettings.challengeKey, SignetSettings.apiURLKey])
    }

    @Test func inMemoryKernelStartsAtGenesisBlock() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let kernel = try BitcoinKernel(storageRoot: tmp, inMemory: true)
        let tip = try kernel.currentTip()
        #expect(tip.height == 0)
    }

    @Test func isLoggingAvailableMatchesBuildFlag() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled == KernelLogSettings.isLoggingAvailable)
    }

    @Test func snapshotAlwaysDisabledWhenLoggingUnavailable() async throws {
        guard !KernelLogSettings.isLoggingAvailable else {
            return
        }

        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: KernelLogSettings.loggingEnabledKey)
        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(!snapshot.isEnabled)
        #expect(!snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test func repeatedInMemoryKernelStartupWorksWhenLoggingUnavailable() async throws {
        guard !KernelLogSettings.isLoggingAvailable else {
            return
        }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let firstKernel = try BitcoinKernel(storageRoot: tempRoot.appendingPathComponent("first"), inMemory: true)
        let secondKernel = try BitcoinKernel(storageRoot: tempRoot.appendingPathComponent("second"), inMemory: true)

        #expect(try firstKernel.currentTip().height == 0)
        #expect(try secondKernel.currentTip().height == 0)
    }
}
