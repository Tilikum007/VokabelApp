import Foundation

public struct VocabularyBackendClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURLs: [URL]

    public init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURLs = baseURL.map { [$0] } ?? VocabularyBackendConfiguration.defaultBaseURLs
        self.session = session
    }

    public init(baseURLs: [URL], session: URLSession = .shared) {
        self.baseURLs = Self.uniqueURLs(baseURLs)
        self.session = session
    }

    public func sync(request: BackendSyncRequest) async throws -> BackendSyncResponse {
        try await post(path: "/v1/sync", body: request)
    }

    public func checkVocabularyUpdates(request: BackendVocabularyUpdateRequest) async throws -> BackendVocabularyUpdateResponse {
        try await post(path: "/v1/vocabulary/updates", body: request)
    }

    private func post<Request: Encodable, Response: Decodable>(path: String, body: Request) async throws -> Response {
        guard !baseURLs.isEmpty else {
            throw VocabularyBackendClientError.missingBaseURL
        }

        var lastError: Error?
        Self.writeDiagnostics("POST \(path): trying \(baseURLs.map(\.absoluteString).joined(separator: ", "))")
        for baseURL in baseURLs {
            do {
                let response: Response = try await post(path: path, body: body, baseURL: baseURL)
                Self.writeDiagnostics("POST \(path): success via \(baseURL.absoluteString)")
                return response
            } catch {
                Self.writeDiagnostics("POST \(path): failed via \(baseURL.absoluteString): \(error.localizedDescription)")
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw VocabularyBackendClientError.missingBaseURL
    }

    private func post<Request: Encodable, Response: Decodable>(path: String, body: Request, baseURL: URL) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder.backendEncoder
        request.httpBody = try encoder.encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw VocabularyBackendClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                throw VocabularyBackendClientError.httpStatus(http.statusCode, message)
            }

            do {
                return try JSONDecoder.backendDecoder.decode(Response.self, from: data)
            } catch {
                throw VocabularyBackendClientError.decodingFailed(error.localizedDescription)
            }
        } catch let error as VocabularyBackendClientError {
            throw error
        } catch let error as URLError {
            throw VocabularyBackendClientError.networkFailed(baseURL.absoluteString, error.localizedDescription)
        } catch {
            throw VocabularyBackendClientError.networkFailed(baseURL.absoluteString, error.localizedDescription)
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func writeDiagnostics(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"

        do {
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = directory.appending(path: "backend-diagnostics.log")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Backend diagnostics unavailable: \(error.localizedDescription)")
        }
    }
}

public enum VocabularyBackendConfiguration {
    public static var defaultBaseURL: URL? {
        defaultBaseURLs.first
    }

    public static var defaultBaseURLs: [URL] {
        var values: [String] = []

        if let override = UserDefaults.standard.string(forKey: "vokabelapp.backendBaseURL"),
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(override)
        }

        if let environment = ProcessInfo.processInfo.environment["VOKABEL_BACKEND_BASE_URL"],
           !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(environment)
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "VokabelBackendBaseURL") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(value)
        }

        if let fallbackValues = Bundle.main.object(forInfoDictionaryKey: "VokabelBackendFallbackBaseURLs") as? [String] {
            values.append(contentsOf: fallbackValues)
        }

        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return url
        }
    }
}

public struct BackendSyncRequest: Encodable, Equatable, Sendable {
    public var deviceID: String
    public var knownCatalogEntryIDs: [String]
    public var progressEvents: [ProgressEvent]

    public init(deviceID: String, knownCatalogEntryIDs: [String], progressEvents: [ProgressEvent]) {
        self.deviceID = deviceID
        self.knownCatalogEntryIDs = knownCatalogEntryIDs
        self.progressEvents = progressEvents
    }
}

public struct BackendSyncResponse: Decodable, Equatable, Sendable {
    public var catalogCSV: String
    public var progressEvents: [ProgressEvent]
    public var catalogVersion: String?
    public var newVocabularyCount: Int
    public var correctedVocabularyCount: Int

    public init(
        catalogCSV: String,
        progressEvents: [ProgressEvent],
        catalogVersion: String? = nil,
        newVocabularyCount: Int = 0,
        correctedVocabularyCount: Int = 0
    ) {
        self.catalogCSV = catalogCSV
        self.progressEvents = progressEvents
        self.catalogVersion = catalogVersion
        self.newVocabularyCount = newVocabularyCount
        self.correctedVocabularyCount = correctedVocabularyCount
    }
}

public struct BackendVocabularyUpdateRequest: Encodable, Equatable, Sendable {
    public var deviceID: String
    public var knownCatalogEntryIDs: [String]

    public init(deviceID: String, knownCatalogEntryIDs: [String]) {
        self.deviceID = deviceID
        self.knownCatalogEntryIDs = knownCatalogEntryIDs
    }
}

public struct BackendVocabularyUpdateResponse: Decodable, Equatable, Sendable {
    public var catalogCSV: String?
    public var catalogVersion: String?
    public var newVocabularyCount: Int
    public var correctedVocabularyCount: Int

    public init(
        catalogCSV: String?,
        catalogVersion: String? = nil,
        newVocabularyCount: Int = 0,
        correctedVocabularyCount: Int = 0
    ) {
        self.catalogCSV = catalogCSV
        self.catalogVersion = catalogVersion
        self.newVocabularyCount = newVocabularyCount
        self.correctedVocabularyCount = correctedVocabularyCount
    }
}

public enum VocabularyBackendClientError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidResponse
    case httpStatus(Int, String?)
    case networkFailed(String, String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Backend-Adresse fehlt. Bitte VokabelBackendBaseURL konfigurieren."
        case .invalidResponse:
            return "Backend hat keine gueltige HTTP-Antwort geliefert"
        case let .httpStatus(status, body):
            if let body, !body.isEmpty {
                return "Backend HTTP \(status): \(body)"
            }
            return "Backend HTTP \(status)"
        case let .networkFailed(baseURL, reason):
            return "Backend nicht erreichbar (\(baseURL)). Bitte pruefen, ob Mac und iPhone im selben WLAN sind, USB-Fallback aktiv ist und lokaler Netzwerkzugriff erlaubt ist. Details: \(reason)"
        case let .decodingFailed(reason):
            return "Backend-Antwort konnte nicht gelesen werden. Details: \(reason)"
        }
    }
}

private extension JSONEncoder {
    static var backendEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var backendDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
