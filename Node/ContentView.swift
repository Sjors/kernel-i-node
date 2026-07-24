//
//  ContentView.swift
//  Node
//
//  Created by Sjors Provoost on 14/03/2026.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    let viewModel: NodeViewModel
    @State private var pendingReindexMode: ReindexMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Signet Kernel Sync")
                .font(.title.bold())

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * viewModel.snapshot.progressFraction)
                }
            }
            .frame(height: 6)

            LabeledContent("Progress", value: progressLabel)
            LabeledContent("Height", value: "\(viewModel.snapshot.localHeight) / \(viewModel.snapshot.remoteHeight)")
            ViewThatFits {
                LabeledContent {
                    tipHashText
                } label: {
                    Text("Tip Hash")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip Hash")
                    tipHashText
                }
            }

            if case .failed(let message) = viewModel.snapshot.phase {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if !viewModel.snapshot.isComplete {
                Text("This app downloads signet blocks from mempool.space and feeds them to libbitcoinkernel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Divider()

            HStack(spacing: 12) {
                Button(viewModel.isSyncEnabled ? "Stop" : "Start") {
                    viewModel.toggleSync()
                }

                settingsButton

                Spacer()

                Button {
                    viewModel.toggleNetwork()
                } label: {
                    Label("Network",
                          systemImage: viewModel.isNetworkEnabled ? "largecircle.fill.circle" : "circle")
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Dangerous")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text("These actions restart the kernel and rebuild local validation state from the stored block files.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Reindex Chainstate", role: .destructive) {
                        pendingReindexMode = .chainstate
                    }

                    Button("Full Reindex", role: .destructive) {
                        pendingReindexMode = .full
                    }
                }
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 280, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
        .confirmationDialog(
            pendingReindexMode?.confirmationTitle ?? "Reindex",
            isPresented: Binding(
                get: { pendingReindexMode != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingReindexMode = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingReindexMode {
                Button(pendingReindexMode.confirmationTitle, role: .destructive) {
                    viewModel.requestReindex(pendingReindexMode)
                    self.pendingReindexMode = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingReindexMode = nil
            }
        } message: {
            Text(pendingReindexMode?.confirmationMessage ?? "")
        }
        .task {
            viewModel.startIfNeeded()
        }
    }

    private var progressLabel: String {
        let percent = viewModel.snapshot.progressFraction * 100
        return String(format: "%.1f%%", percent)
    }

    @ViewBuilder
    private var settingsButton: some View {
        #if os(macOS)
        SettingsLink {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Settings")
        #elseif os(iOS)
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        #endif
    }

    private var tipHashLabel: String {
        if viewModel.snapshot.tipHash.isEmpty {
            return "Unavailable"
        }
        return viewModel.snapshot.tipHash
    }

    private var tipHashText: some View {
        Text(tipHashLabel)
            .font(.callout.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
    }
}

#Preview {
    ContentView(viewModel: NodeViewModel())
}
