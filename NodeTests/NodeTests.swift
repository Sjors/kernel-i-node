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

    @Test func kernelLogSettingsDefaultSnapshotDisablesNamedCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled)
        #expect(snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test func kernelLogSettingsMasterToggleDisablesAllCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.loggingEnabledKey)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(!snapshot.isEnabled)
        #expect(!snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test func kernelLogSettingsInternalLogsTogglePreservesCategories() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.internalLogsEnabledKey)

        let snapshot = KernelLogSettings.snapshot(defaults)
        #expect(snapshot.isEnabled)
        #expect(!snapshot.internalLogsEnabled)
        #expect(snapshot.enabledCategories.isEmpty)
    }

    @Test func kernelLogSettingsCategoryToggleRemovesOnlyThatCategory() async throws {
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

    @Test func kernelLogSettingsCategoryHelperTracksValidationToggle() async throws {
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

    @Test func kernelLogSettingsCategoryHelperRespectsMasterToggle() async throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        KernelLogSettings.registerDefaults(defaults)
        defaults.set(false, forKey: KernelLogSettings.loggingEnabledKey)

        #expect(!KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryValidation, defaults: defaults))
        #expect(!KernelLogSettings.isCategoryEnabled(KernelLogSettings.kernelLogCategoryKernel, defaults: defaults))
    }

    @Test func kernelLogSettingsParsesTaggedRawLogCategories() async throws {
        #expect(KernelLogSettings.categoryForRawLogLine("[validation] Enqueuing BlockConnected:") == KernelLogSettings.kernelLogCategoryValidation)
        #expect(KernelLogSettings.categoryForRawLogLine("[kernel] something happened") == KernelLogSettings.kernelLogCategoryKernel)
        #expect(
            KernelLogSettings.categoryForRawLogLine("2026-03-20T21:24:29Z [validation] Enqueuing BlockConnected:")
            == KernelLogSettings.kernelLogCategoryValidation
        )
    }

    @Test func kernelLogSettingsLeavesUntaggedRawLogLinesAlone() async throws {
        #expect(KernelLogSettings.categoryForRawLogLine("UpdateTip: new best=...") == nil)
        #expect(KernelLogSettings.categoryForRawLogLine("[unknown] something") == nil)
        #expect(KernelLogSettings.categoryForRawLogLine("2026-03-20T21:24:29Z UpdateTip: new best=...") == nil)
    }

    @Test func iOSSettingsBundleDefaultsMatchKernelLogSettingsDefaults() async throws {
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
    }
}
