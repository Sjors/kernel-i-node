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
#elseif os(iOS)
import UIKit
#endif

@main
struct NodeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = NodeViewModel()

    init() {
        KernelLogSettings.registerDefaults()
        BitcoinKernel.refreshRuntimeLogSettings()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear(perform: configurePlatformHooks)
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    viewModel.refreshKernelLogging()
                }
                .onReceive(NotificationCenter.default.publisher(for: KernelLogSettings.didChangeNotification)) { _ in
                    viewModel.refreshKernelLogging()
                }
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    KernelLogSettings.registerDefaults()
                    viewModel.refreshKernelLogging()
                }
                #elseif os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    KernelLogSettings.registerDefaults()
                    viewModel.refreshKernelLogging()
                }
                #endif
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        KernelLogSettings.registerDefaults()
                        viewModel.refreshKernelLogging()
                    }
                }
        }
        #if os(macOS)
        Settings {
            KernelLogSettingsView()
        }
        #endif
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
