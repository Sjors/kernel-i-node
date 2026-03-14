//
//  NodeApp.swift
//  Node
//
//  Created by Sjors Provoost on 14/03/2026.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (@MainActor () async -> Void)?
    private var terminationInProgress = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationInProgress {
            return .terminateLater
        }

        guard let terminationHandler else {
            return .terminateNow
        }

        terminationInProgress = true

        Task { @MainActor in
            await terminationHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

@main
struct NodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = NodeViewModel()

    var body: some Scene {
        let viewModel = viewModel
        appDelegate.terminationHandler = { [viewModel] in
            await viewModel.prepareForTermination()
        }

        return WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
