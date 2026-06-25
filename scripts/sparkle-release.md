# Sparkle auto-update — release guide

Kekasatori uses [Sparkle 2](https://sparkle-project.org) for auto-updates
(direct distribution). The updater reads `SUFeedURL` and `SUPublicEDKey` from the
app's Info.plist (set as build settings in the project).

## One-time setup

1. **Generate the EdDSA signing key** (private key stays in your Keychain):
   ```sh
   # Sparkle's tools ship inside the resolved package artifacts:
   BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin' -type d | head -1)
   "$BIN/generate_keys"
   ```
   It prints a **public** key. Put it in the project build setting
   `INFOPLIST_KEY_SUPublicEDKey` (replace `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY`).
   Keep the private key safe — losing it breaks future updates.

2. **Set the feed URL** to where you'll host the appcast. Current placeholder:
   `https://kekasatori.app/updates/appcast.xml` — change the
   `INFOPLIST_KEY_SUFeedURL` build setting to your real URL.

## Per-release

1. Build + notarize the DMG:
   ```sh
   DEV_ID_APP="Developer ID Application: … (TEAMID)" TEAM_ID=… \
   NOTARY_PROFILE=… ./Scripts/package-and-notarize.sh
   ```

2. Generate / update the appcast (signs the DMG with your EdDSA private key and
   writes/updates `appcast.xml`):
   ```sh
   BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin' -type d | head -1)
   "$BIN/generate_appcast" ./build/   # folder containing the .dmg
   ```
   This produces `build/appcast.xml` with the correct version, length, and
   `sparkle:edSignature`.

3. Upload **both** the `.dmg` and `appcast.xml` to your host at the `SUFeedURL`
   location. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the project
   before each release so Sparkle detects the new build.

## Notes
- The "Check for Updates…" menu item is under the app menu (see
  `Services/AppUpdater.swift`).
- Sparkle also checks automatically in the background on its default schedule.
- Hosting must serve the DMG over HTTPS.
