import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public var email: String
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(email: String, accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}
