# VokabelApp

Native SwiftUI vocabulary trainer for macOS, iOS and iPadOS.

The app is currently structured as:

- Swift Package for local development and command-line verification.
- `project.yml` for generating a signed iOS/iPadOS/macOS Xcode app with XcodeGen.
- `App/Info.plist` template for backend configuration.

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

## Backend Sync

The canonical master file is no longer owned by Google Drive. The backend owns:

`MASTER_vokabelheft_norwegisch.csv`

The app talks to the backend through:

- `POST /v1/sync`
- `POST /v1/vocabulary/updates`

Configure the backend base URL with one of:

- `VokabelBackendBaseURL` in `App/Info.plist`
- `VOKABEL_BACKEND_BASE_URL` in the process environment
- `UserDefaults` key `vokabelapp.backendBaseURL`

The app-side REST client is `VocabularyBackendClient`. The backend contract is documented in:

`Docs/BACKEND_CONTRACT.md`

The repository also contains a small standard-library reference backend:

`Backend/vokabel_backend.py`

Google Drive support remains in the codebase as a legacy migration path, but app sync buttons now use the backend client.

## Legacy Google Drive

The previous Drive master file ID was:

`1JlZTzcUYnJAu3piX0oVCtxmoOI8Bcgy1`
