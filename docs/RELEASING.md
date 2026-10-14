# Releasing Portly

Portly ships outside the Mac App Store. It can't be sandboxed, because it needs to inspect other processes. The target is already configured for Developer ID distribution: **Hardened Runtime on**, **App Sandbox off**, and no special entitlements. (Process inspection, signals and launching your own processes need none.)

## Prerequisites

1. An Apple Developer Program membership.
2. A **Developer ID Application** certificate in your keychain: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application.
3. An app-specific password for your Apple ID (account.apple.com), or an App Store Connect API key.

Set your own team ID in `ExportOptions.plist` and in the target's signing settings if you're building from a fork.

## Steps

```sh
# On Intel Macs with Xcode 26.5, export SWIFT_USE_OLD_DRIVER=1 first (see README).

# 1. Archive
xcodebuild -project Portly.xcodeproj -scheme Portly -configuration Release \
  -archivePath build/Portly.xcarchive archive

# 2. Export, signed with Developer ID
xcodebuild -exportArchive -archivePath build/Portly.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist

# 3. Notarize (store credentials once, then submit)
xcrun notarytool store-credentials portly-notary \
  --apple-id "<your Apple ID>" --team-id "<your team ID>" --password "<app-specific password>"
ditto -c -k --keepParent build/export/Portly.app build/Portly.zip
xcrun notarytool submit build/Portly.zip --keychain-profile portly-notary --wait

# 4. Staple and verify
xcrun stapler staple build/export/Portly.app
spctl --assess --type execute -vv build/export/Portly.app   # → source=Notarized Developer ID

# 5. Zip the stapled app for the GitHub release
ditto -c -k --keepParent build/export/Portly.app build/Portly-<version>.zip
```

If you distribute a DMG instead, sign and notarize the DMG too. If a submission is rejected, `xcrun notarytool log <submission-id> --keychain-profile portly-notary` explains why.

## Notes

- Launch at login uses `SMAppService.mainApp`. It works best when Portly is in `/Applications`. If macOS asks for approval, Portly's Settings shows a button that opens System Settings → Login Items.
- Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the target's build settings before each release.
