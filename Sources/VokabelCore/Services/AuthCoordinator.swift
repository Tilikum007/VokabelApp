import Foundation

@MainActor
public final class AuthCoordinator: ObservableObject {
    @Published public private(set) var session: AuthSession?
    @Published public var rememberLogin: Bool
    @Published public private(set) var statusMessage: String

    private let keychain: KeychainSessionStore
    private let googleSignIn: GoogleSignInSessionProvider
    private let rememberKey = "rememberGoogleLogin"

    public init(
        keychain: KeychainSessionStore = KeychainSessionStore(),
        googleSignIn: GoogleSignInSessionProvider = GoogleSignInSessionProvider()
    ) {
        self.keychain = keychain
        self.googleSignIn = googleSignIn
        self.rememberLogin = UserDefaults.standard.bool(forKey: rememberKey)
        self.statusMessage = "Nicht angemeldet"
    }

    public var isSignedIn: Bool {
        session != nil
    }

    public var email: String {
        session?.email ?? ""
    }

    public var accessToken: String? {
        session?.accessToken
    }

    public func restoreSavedLogin() async {
        if let googleSession = await googleSignIn.restorePreviousSession() {
            acceptGoogleSession(googleSession)
            return
        }

        guard rememberLogin else { return }

        do {
            if let saved = try keychain.load(), !saved.isExpired {
                session = saved
                statusMessage = "Angemeldet als \(saved.email)"
            } else {
                statusMessage = "Anmeldung erneuern"
            }
        } catch {
            statusMessage = "Gespeicherte Anmeldung nicht lesbar"
        }
    }

    public func updateRememberLogin(_ enabled: Bool) {
        rememberLogin = enabled
        UserDefaults.standard.set(enabled, forKey: rememberKey)

        if !enabled {
            try? keychain.clear()
            statusMessage = session == nil ? "Nicht angemeldet" : "Anmeldung wird nicht gespeichert"
        } else if let session {
            try? keychain.save(session)
        }
    }

    public func acceptGoogleSession(_ session: AuthSession) {
        self.session = session
        statusMessage = "Angemeldet als \(session.email)"

        if rememberLogin {
            try? keychain.save(session)
        }
    }

    public func signIn() async {
        do {
            acceptGoogleSession(try await googleSignIn.signInFromCurrentContext())
        } catch {
            statusMessage = "Google-Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    public func handleOpenURL(_ url: URL) -> Bool {
        googleSignIn.handleOpenURL(url)
    }

    public func signOut() {
        session = nil
        googleSignIn.signOut()
        try? keychain.clear()
        statusMessage = "Abgemeldet"
    }
}
