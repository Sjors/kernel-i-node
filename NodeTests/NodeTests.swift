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
}
