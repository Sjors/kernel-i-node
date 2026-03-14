import Foundation

actor MempoolRequestPacer {
    private var lastRequestFinishedAtNanoseconds: UInt64?

    func waitIfNeeded(minimumDelayNanoseconds: UInt64) async throws {
        guard let lastRequestFinishedAtNanoseconds else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= lastRequestFinishedAtNanoseconds ? now - lastRequestFinishedAtNanoseconds : 0
        guard elapsed < minimumDelayNanoseconds else {
            return
        }

        try await Task.sleep(nanoseconds: minimumDelayNanoseconds - elapsed)
    }

    func markRequestCompleted() {
        lastRequestFinishedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
    }
}

struct MempoolBlockSummary: Decodable, Sendable {
    let id: String
    let height: Int
}

enum MempoolClientError: LocalizedError {
    case unexpectedStatusCode(Int)
    case invalidBlockBatch(Int)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatusCode(statusCode):
            return "Server returned HTTP \(statusCode)"
        case let .invalidBlockBatch(startHeight):
            return "Server returned an invalid block batch for height \(startHeight)."
        }
    }
}

struct MempoolClient {
    private static let requestPacer = MempoolRequestPacer()

    let session: URLSession
    let baseURL: URL
    let maximumRetryCount: Int
    let baseRetryDelayMilliseconds: UInt64
    let minimumInterRequestDelayMilliseconds: UInt64

    nonisolated init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://mempool.space/signet/api")!,
        maximumRetryCount: Int = 5,
        baseRetryDelayMilliseconds: UInt64 = 500,
        minimumInterRequestDelayMilliseconds: UInt64 = 100
    ) {
        self.session = session
        self.baseURL = baseURL
        self.maximumRetryCount = maximumRetryCount
        self.baseRetryDelayMilliseconds = baseRetryDelayMilliseconds
        self.minimumInterRequestDelayMilliseconds = minimumInterRequestDelayMilliseconds
    }

    func fetchTipHeight() async throws -> Int {
        let data = try await fetchData(path: "blocks/tip/height")
        guard let height = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.cannotParseResponse)
        }
        return height
    }

    func fetchBlocks(startingAt height: Int) async throws -> [MempoolBlockSummary] {
        let data = try await fetchData(path: "v1/blocks/\(height)")

        do {
            return try JSONDecoder().decode([MempoolBlockSummary].self, from: data)
        } catch {
            throw MempoolClientError.invalidBlockBatch(height)
        }
    }

    func fetchRawBlock(hash: String) async throws -> Data {
        try await fetchData(path: "block/\(hash)/raw")
    }

    private func fetchData(path: String) async throws -> Data {
        let url = baseURL.appending(path: path, directoryHint: .notDirectory)

        for attempt in 0...maximumRetryCount {
            try await Self.requestPacer.waitIfNeeded(
                minimumDelayNanoseconds: nanoseconds(fromMilliseconds: minimumInterRequestDelayMilliseconds)
            )

            do {
                let (data, response) = try await session.data(from: url)
                await Self.requestPacer.markRequestCompleted()

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if 200 ..< 300 ~= httpResponse.statusCode {
                    return data
                }

                if attempt < maximumRetryCount, shouldRetry(statusCode: httpResponse.statusCode) {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: httpResponse, attempt: attempt))
                    continue
                }

                throw MempoolClientError.unexpectedStatusCode(httpResponse.statusCode)
            } catch {
                await Self.requestPacer.markRequestCompleted()

                guard attempt < maximumRetryCount, shouldRetry(error: error) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: nil, attempt: attempt))
            }
        }

        throw URLError(.unknown)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 429 || (500 ... 599).contains(statusCode)
    }

    private func shouldRetry(error: any Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func retryDelayNanoseconds(for response: HTTPURLResponse?, attempt: Int) -> UInt64 {
        if
            let retryAfter = response?.value(forHTTPHeaderField: "Retry-After"),
            let seconds = TimeInterval(retryAfter),
            seconds > 0
        {
            return UInt64(seconds * 1_000_000_000)
        }

        let multiplier = 1 << min(attempt, 6)
        return nanoseconds(fromMilliseconds: baseRetryDelayMilliseconds * UInt64(multiplier))
    }

    private func nanoseconds(fromMilliseconds milliseconds: UInt64) -> UInt64 {
        milliseconds * 1_000_000
    }
}
