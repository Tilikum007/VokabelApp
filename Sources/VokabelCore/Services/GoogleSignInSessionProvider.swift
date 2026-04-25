import Foundation

#if canImport(GoogleSignIn)
import GoogleSignIn

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public final class GoogleSignInSessionProvider {
    public static let driveScope = "https://www.googleapis.com/auth/drive"

    public init() {}

    public func restorePreviousSession() async -> AuthSession? {
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user.map(Self.makeSession))
            }
        }
    }

    public func signInFromCurrentContext() async throws -> AuthSession {
        #if os(iOS)
        guard let viewController = Self.currentViewController() else {
            throw GoogleSignInSessionProviderError.missingPresentationContext
        }
        return try await signIn(presenting: viewController)
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            throw GoogleSignInSessionProviderError.missingPresentationContext
        }
        return try await signIn(presenting: window)
        #else
        throw GoogleSignInSessionProviderError.unsupportedPlatform
        #endif
    }

    #if os(iOS)
    public func signIn(presenting viewController: UIViewController) async throws -> AuthSession {
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: [Self.driveScope]
        )
        return Self.makeSession(from: result.user)
    }
    #elseif os(macOS)
    public func signIn(presenting window: NSWindow) async throws -> AuthSession {
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: [Self.driveScope]
        )
        return Self.makeSession(from: result.user)
    }
    #endif

    public func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    public func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    nonisolated private static func makeSession(from user: GIDGoogleUser) -> AuthSession {
        AuthSession(
            email: user.profile?.email ?? "Google",
            accessToken: user.accessToken.tokenString,
            refreshToken: user.refreshToken.tokenString,
            expiresAt: user.accessToken.expirationDate
        )
    }

    #if os(iOS)
    private static func currentViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        return topViewController(from: root)
    }

    private static func topViewController(from viewController: UIViewController?) -> UIViewController? {
        if let navigation = viewController as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = viewController as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = viewController?.presentedViewController {
            return topViewController(from: presented)
        }
        return viewController
    }
    #endif
}

public enum GoogleSignInSessionProviderError: LocalizedError {
    case missingPresentationContext
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .missingPresentationContext:
            "Kein Fenster fuer Google Sign-In gefunden"
        case .unsupportedPlatform:
            "Google Sign-In wird auf dieser Plattform nicht unterstuetzt"
        }
    }
}
#else
@MainActor
public final class GoogleSignInSessionProvider {
    public static let driveScope = "https://www.googleapis.com/auth/drive"

    public init() {}

    public func restorePreviousSession() async -> AuthSession? {
        nil
    }

    public func signInFromCurrentContext() async throws -> AuthSession {
        throw GoogleSignInSessionProviderError.googleSignInPackageMissing
    }

    public func signOut() {}

    public func handleOpenURL(_ url: URL) -> Bool {
        false
    }
}

public enum GoogleSignInSessionProviderError: LocalizedError {
    case googleSignInPackageMissing

    public var errorDescription: String? {
        "Google Sign-In Paket ist im Build nicht eingebunden"
    }
}
#endif
