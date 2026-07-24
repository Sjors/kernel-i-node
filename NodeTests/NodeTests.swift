//
//  NodeTests.swift
//  NodeTests
//
//  Created by Sjors Provoost on 14/03/2026.
//

import Foundation
import Testing
@testable import Node

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
