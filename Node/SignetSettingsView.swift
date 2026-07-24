import SwiftUI

struct SignetSettingsView: View {
    @AppStorage(SignetSettings.challengeKey) private var challengeHex = ""
    @AppStorage(SignetSettings.apiURLKey) private var apiURLString = ""

    var body: some View {
        Form {
            Section {
                TextField("Challenge (hex)", text: $challengeHex, prompt: Text("Default signet challenge"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                TextField("API URL", text: $apiURLString, prompt: Text(SignetSettings.defaultAPIBaseURL.absoluteString))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                if let validationMessage {
                    Text(validationMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Custom Signet")
            } footer: {
                Text("Leave both fields empty for the default signet. A custom challenge uses its own storage directory and needs an Esplora-compatible API serving that signet. Changes take effect the next time sync starts.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }

    private var validationMessage: String? {
        let trimmedChallenge = challengeHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedChallenge.isEmpty, SignetSettings.data(fromHex: trimmedChallenge) == nil {
            return SignetSettingsError.invalidChallengeHex.localizedDescription
        }

        let trimmedURL = apiURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            guard let url = URL(string: trimmedURL), url.scheme == "http" || url.scheme == "https" else {
                return SignetSettingsError.invalidAPIURL.localizedDescription
            }
        }

        return nil
    }
}

#Preview {
    SignetSettingsView()
}
