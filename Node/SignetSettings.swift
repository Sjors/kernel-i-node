import Foundation

struct SignetSettingsSnapshot: Equatable, Sendable {
    /// Raw signet challenge script, or nil to use the default signet.
    let challenge: Data?
    /// Base URL of the Esplora-compatible block source API.
    let apiBaseURL: URL
}

enum SignetSettingsError: LocalizedError {
    case invalidChallengeHex
    case invalidAPIURL

    var errorDescription: String? {
        switch self {
        case .invalidChallengeHex:
            return "The custom signet challenge is not valid hex. Fix or clear it in Settings."
        case .invalidAPIURL:
            return "The custom signet API URL is not a valid http(s) URL. Fix or clear it in Settings."
        }
    }
}

enum SignetSettings {
    static let challengeKey = "signet_custom_challenge"
    static let apiURLKey = "signet_custom_api_url"
    static let defaultAPIBaseURL = URL(string: "https://mempool.space/signet/api")!

    /// Reads the custom signet preferences. Empty values fall back to the
    /// default signet challenge and the default mempool.space API.
    static func snapshot(_ defaults: UserDefaults = .standard) throws -> SignetSettingsSnapshot {
        let challengeHex = (defaults.string(forKey: challengeKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiURLString = (defaults.string(forKey: apiURLKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let challenge: Data?
        if challengeHex.isEmpty {
            challenge = nil
        } else {
            guard let parsed = data(fromHex: challengeHex) else {
                throw SignetSettingsError.invalidChallengeHex
            }
            challenge = parsed
        }

        let apiBaseURL: URL
        if apiURLString.isEmpty {
            apiBaseURL = defaultAPIBaseURL
        } else {
            guard let parsed = URL(string: apiURLString), parsed.scheme == "http" || parsed.scheme == "https" else {
                throw SignetSettingsError.invalidAPIURL
            }
            apiBaseURL = parsed
        }

        return SignetSettingsSnapshot(challenge: challenge, apiBaseURL: apiBaseURL)
    }

    static func data(fromHex hex: String) -> Data? {
        let characters = Array(hex)
        guard !characters.isEmpty, characters.count % 2 == 0 else {
            return nil
        }

        var bytes = Data(capacity: characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = characters[index].hexDigitValue, let low = characters[index + 1].hexDigitValue else {
                return nil
            }
            bytes.append(UInt8(high << 4 | low))
            index += 2
        }
        return bytes
    }
}
