import Foundation

public struct GoogleDriveClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func downloadCSV(fileID: String, accessToken: String) async throws -> String {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return String(decoding: data, as: UTF8.self)
    }

    public func uploadCSV(_ csv: String, fileID: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/csv; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.upload(for: request, from: Data(csv.utf8))
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
