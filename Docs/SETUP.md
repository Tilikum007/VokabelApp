# Setup

## GitHub

Create a public repository named `VokabelApp`, then add it as the remote:

```sh
git config user.name "YOUR_NAME"
git config user.email "YOUR_EMAIL"
git remote add origin git@github.com:YOUR_USER/VokabelApp.git
git branch -M main
git add .
git commit -m "Initial VokabelApp"
git push -u origin main
```

## Xcode

This repository is currently a Swift Package plus an XcodeGen project description.

Install XcodeGen, then run:

```sh
brew install xcodegen
xcodegen generate
open VokabelApp.xcodeproj
```

## Backend

The app syncs vocabulary through the backend contract in:

`Docs/BACKEND_CONTRACT.md`

The canonical development data source is the running backend data directory:

```text
/Users/patrickstange/Library/Application Support/VokabelAppBackend/data
```

Refresh the repository fallback snapshot from that data source when needed:

```sh
cp "/Users/patrickstange/Library/Application Support/VokabelAppBackend/data/MASTER_vokabelheft_norwegisch.csv" \
  Sources/VokabelCore/Resources/MASTER_vokabelheft_norwegisch.csv
```

Set the backend URL in `App/Info.plist`:

```xml
<key>VokabelBackendBaseURL</key>
<string>https://example.com</string>
```

For local development, the app also accepts:

- environment variable `VOKABEL_BACKEND_BASE_URL`
- `UserDefaults` key `vokabelapp.backendBaseURL`

Google Drive sync remains in the source as a legacy migration path, but the visible app sync actions use the backend.

## Local Backend

Run the reference backend locally:

```sh
python3 Backend/vokabel_backend.py --host 127.0.0.1 --port 8080
```

Then configure the app with:

```text
VOKABEL_BACKEND_BASE_URL=http://127.0.0.1:8080
```

`Backend/Data/` is ignored by Git and is only a local runtime cache. The app and future imports should use the running backend under `Application Support` as the source of truth unless explicitly told otherwise.

## TestFlight

Prerequisites:

- Apple Developer membership for team `Y3B24T9MUD`.
- App Store Connect app record for bundle ID `de.papa.tiliku` with SKU `Tiliku00002`.
- Xcode account or App Store Connect API key with permission to create signing assets and upload builds.
- A reachable production or beta backend URL for testers. The default hosted backend is `https://vokabel.37.27.90.180.sslip.io`.

Prepare and upload a TestFlight archive. By default the script uses the hosted backend on Servergroß:

```sh
Scripts/archive-testflight.sh
```

To override the backend URL for a specific archive, set it explicitly:

```sh
VOKABEL_BACKEND_BASE_URL=https://your-backend.example.com Scripts/archive-testflight.sh
```

The script regenerates `VokabelApp.xcodeproj`, archives the iOS app with automatic signing, and exports/uploads using `Configs/ExportOptions-TestFlight.plist`.

After upload, open App Store Connect, wait for processing, add beta metadata, and invite internal testers. External testers require Beta App Review.
