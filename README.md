# VokabelApp

Native SwiftUI vocabulary trainer for macOS, iOS and iPadOS.

The app is currently structured as:

- Swift Package for local development and command-line verification.
- `project.yml` for generating a signed iOS/iPadOS/macOS Xcode app with XcodeGen.
- `App/Info.plist` template for Google Sign-In configuration.

## Training Rules

- Learners: Papa and Mama.
- Filters: level, source, lesson, level + source, level + lesson.
- Levels range from 0 to 5.
- Correct answers add 1 level, almost correct answers keep the level, wrong answers subtract 1 level.
- Low levels and entries not asked for a long time are preferred.
- The same word is not repeated immediately.
- CSV IDs are never changed.
- After every answer the local CSV copy is updated.

## Platform Behavior

- macOS uses typed answers.
- iOS and iPadOS use five answer options and one vocabulary item per round.

## Google Drive

The master file is configured as:

`MASTER_vokabelheft_norwegisch.csv`

Drive file ID:

`1JlZTzcUYnJAu3piX0oVCtxmoOI8Bcgy1`

The REST client is present in `GoogleDriveClient`. A production build still needs Google OAuth client configuration for Apple platforms before sync buttons should be exposed in the UI.

### OAuth Recommendation

Use Google Sign-In for iOS and macOS via Swift Package Manager:

`https://github.com/google/GoogleSignIn-iOS`

Recommended package products:

- `GoogleSignIn`
- `GoogleSignInSwift`

The optional adapter is already present in:

`Sources/VokabelCore/Services/GoogleSignInSessionProvider.swift`

Recommended Drive scope:

`https://www.googleapis.com/auth/drive`

This keeps the app limited to files opened by or shared with the app instead of requesting unrestricted Drive access.

Avoid `https://www.googleapis.com/auth/drive` for this app. It is broader than needed for a single vocabulary CSV and creates a heavier verification burden.

### Remember Login

The app includes a Keychain-backed `AuthCoordinator` and an "Anmeldung merken" toggle. The intended production flow is:

1. Try `GoogleSignIn.restorePreviousSignIn()` on app start.
2. If Google returns a valid session, pass the token into `AuthCoordinator.acceptGoogleSession(...)`.
3. If "Anmeldung merken" is enabled, persist the session metadata in Keychain.
4. On sign-out or when the toggle is disabled, clear the Keychain entry.

Do not store Google passwords. The app should only store OAuth session data in Keychain.

Template OAuth plist:

`Sources/VokabelCore/Resources/GoogleOAuthConfig.example.plist`
