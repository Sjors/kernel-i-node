//
//  ContentView.swift
//  Node
//
//  Created by Sjors Provoost on 14/03/2026.
//

import SwiftUI

struct ContentView: View {
    let viewModel: NodeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Signet Kernel Sync")
                .font(.title.bold())

            ProgressView(value: viewModel.snapshot.progressFraction)
                .progressViewStyle(.linear)

            LabeledContent("Progress", value: progressLabel)
            LabeledContent("Height", value: "\(viewModel.snapshot.localHeight) / \(viewModel.snapshot.remoteHeight)")
            LabeledContent("Tip Hash", value: tipHashLabel)

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

        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 280, alignment: .topLeading)
        .task {
            viewModel.startIfNeeded()
        }
    }

    private var progressLabel: String {
        let percent = viewModel.snapshot.progressFraction * 100
        return String(format: "%.1f%%", percent)
    }

    private var tipHashLabel: String {
        if viewModel.snapshot.tipHash.isEmpty {
            return "Unavailable"
        }
        return viewModel.snapshot.tipHash
    }
}

#Preview {
    ContentView(viewModel: NodeViewModel())
}
