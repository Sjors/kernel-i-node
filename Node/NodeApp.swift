//
//  NodeApp.swift
//  Node
//
//  Created by Sjors Provoost on 14/03/2026.
//

import SwiftUI

#if os(macOS)
import AppKit

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
#endif

@main
struct NodeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var viewModel = NodeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear(perform: configurePlatformHooks)
        }
    }

    private func configurePlatformHooks() {
        #if os(macOS)
        let viewModel = viewModel
        appDelegate.terminationHandler = { [viewModel] in
            await viewModel.prepareForTermination()
        }
        #endif
    }
}
