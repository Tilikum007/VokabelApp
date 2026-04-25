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

## Google OAuth

1. Create or open a Google Cloud project.
2. Enable the Google Drive API.
3. Configure the OAuth consent screen.
4. Create an OAuth client for iOS/macOS.
5. Add this scope:

```text
https://www.googleapis.com/auth/drive.file
```

6. Replace the placeholders in `App/Info.plist`:

```xml
<key>GIDClientID</key>
<string>...</string>
```

and:

```xml
<string>com.googleusercontent.apps...</string>
```

7. In Google Drive, open or share `MASTER_vokabelheft_norwegisch.csv` with the app flow so `drive.file` can access it.

Until the OAuth placeholders are replaced, the app builds and runs locally but Google sign-in cannot complete.
