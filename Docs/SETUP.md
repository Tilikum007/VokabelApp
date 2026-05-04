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
