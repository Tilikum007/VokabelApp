import Foundation

public struct GoogleDriveClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func downloadCSV(fileID: String, accessToken: String) async throws -> String {
        try await downloadText(fileID: fileID, accessToken: accessToken)
    }

    public func downloadText(fileID: String, accessToken: String) async throws -> String {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return String(decoding: data, as: UTF8.self)
    }

    public func uploadCSV(_ csv: String, fileID: String, accessToken: String) async throws {
        try await uploadText(csv, fileID: fileID, mimeType: "text/csv; charset=utf-8", accessToken: accessToken)
    }

    public func uploadText(_ text: String, fileID: String, mimeType: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: Data(text.utf8))
        try validate(response, data: data)
    }

    public func listFiles(query: String, accessToken: String) async throws -> [GoogleDriveFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,parents)"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder.driveDecoder.decode(GoogleDriveFileListResponse.self, from: data).files
    }

    public func getFile(fileID: String, accessToken: String) async throws -> GoogleDriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,modifiedTime,parents"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder.driveDecoder.decode(GoogleDriveFile.self, from: data)
    }

    public func renameFile(fileID: String, newName: String, accessToken: String) async throws {
        let body = try JSONEncoder().encode(["name": newName])
        try await patchMetadata(fileID: fileID, body: body, accessToken: accessToken)
    }

    public func createFolderIfNeeded(named folderName: String, accessToken: String) async throws -> GoogleDriveFile {
        let query = "mimeType = 'application/vnd.google-apps.folder' and trashed = false and name = '\(escapeQuery(folderName))'"
        if let folder = try await listFiles(query: query, accessToken: accessToken)
            .sorted(by: { ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast) })
            .first {
            return folder
        }

        let body = try JSONEncoder().encode([
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        return try await createMetadataOnly(body: body, accessToken: accessToken)
    }

    public func createTextFile(
        name: String,
        text: String,
        mimeType: String,
        parentID: String?,
        accessToken: String
    ) async throws -> GoogleDriveFile {
        var payload: [String: Any] = ["name": name]
        if let parentID {
            payload["parents"] = [parentID]
        }
        let metadata = try JSONSerialization.data(withJSONObject: payload)
        let file = try await createMetadataOnly(body: metadata, accessToken: accessToken)
        try await uploadText(text, fileID: file.id, mimeType: mimeType, accessToken: accessToken)
        return file
    }

    private func createMetadataOnly(body: Data, accessToken: String) async throws -> GoogleDriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: "id,name,mimeType,modifiedTime,parents")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response, data: data)
        return try JSONDecoder.driveDecoder.decode(GoogleDriveFile.self, from: data)
    }

    private func patchMetadata(fileID: String, body: Data, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?supportsAllDrives=true")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response, data: data)
    }

    private func escapeQuery(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleDriveClientError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let message = String(decoding: data, as: UTF8.self)
            throw GoogleDriveClientError.httpStatus(http.statusCode, message)
        }
    }
}

public struct GoogleDriveFile: Decodable, Equatable {
    public var id: String
    public var name: String
    public var mimeType: String?
    public var modifiedTime: Date?
    public var parents: [String]?
}

private struct GoogleDriveFileListResponse: Decodable {
    var files: [GoogleDriveFile]
}

private extension JSONDecoder {
    static var driveDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum GoogleDriveClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Google Drive hat keine gueltige HTTP-Antwort geliefert"
        case let .httpStatus(status, body):
            if body.isEmpty {
                "Google Drive HTTP \(status)"
            } else {
                "Google Drive HTTP \(status): \(body)"
            }
        }
    }
}
