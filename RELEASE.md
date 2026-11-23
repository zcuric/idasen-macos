# Releasing Idasen

Releases use a `vMAJOR.MINOR.PATCH` Git tag. The tag must match
`CFBundleShortVersionString` in `Resources/Info.plist`.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` for a new
   version. Add release notes in the commit or PR description.
2. On an Apple silicon Mac with Xcode 27, run `swift test`, `make package`, and
   `./Scripts/check-release-version.sh vX.Y.Z`.
3. Merge the release commit to `main` and confirm **Build and test macOS app**
   passed. Tag that exact commit and push the tag:

   ```sh
   git checkout main
   git pull --ff-only
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. **Release macOS app** tests the tagged source, checks the version, packages
   `Idasen.app`, verifies the ZIP and SHA-256 checksum, and creates a GitHub
   Release with both files. The site’s Releases link then resolves to it.
5. Download the release ZIP on a clean Mac and check the first-launch experience.

The current workflow produces an Apple silicon (`arm64`) build. The app is
ad-hoc signed, not notarized. People downloading it may need to select
**Open Anyway** in System Settings → Privacy & Security once. Apple Developer
ID signing and notarization require a certificate and credentials that this
repository does not contain. Do not describe these downloads as notarized.

To inspect a download:

```sh
shasum -a 256 -c Idasen-macOS-arm64.zip.sha256
unzip -tq Idasen-macOS-arm64.zip
```

A failed job does not publish a release. Fix the problem in a new commit and
use a new tag; published tags remain fixed.

## Launch checklist

| Area | Included in v1.1.0 | Follow-up |
| --- | --- | --- |
| First run | Guided connection, scan and retry, Bluetooth permission guidance, and one-click demo | Verify first pairing, denied access recovery, and reconnect with a physical IDÅSEN. |
| Desk controls | Live controls first, rolling height readout, visible move progress, and a target that stays put after editing | Check stop and release on real hardware. Verify height calibration with a tape measure. |
| macOS interface | Native split view and toolbar, system sheet, and motion that follows the app and system Reduce Motion preferences | Tour the app with VoiceOver and keyboard-only navigation. Check increased contrast and reduced transparency on macOS 14 and macOS 26 or later. |
| Feature backlog | Presets, menu bar controls, history and CSV, reminders, and keyboard shortcuts are available | Validate controller variants before broadening compatibility. Explore App Shortcuts for opening the dashboard and viewing height. |
| Distribution | Apple silicon ZIP and SHA-256 workflow | Test the downloaded ZIP in a fresh macOS account. For a notarized release, use a Developer ID Application certificate, Hardened Runtime, and a configured notarytool keychain profile. [Apple’s distribution guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/) |
| Website and X | GitHub Pages, connection guide, reference table, X card, and share link | Verify the public download and social preview, then post the announcement from the project owner’s X account. [X announcement](PROMOTION.md) |

### macOS design references

| Topic | Reference |
| --- | --- |
| System navigation and controls | [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) |
| Custom control surfaces | [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) |
| Animation and accessibility | [Apple Human Interface Guidelines for motion](https://developer.apple.com/design/human-interface-guidelines/motion) |
| Download verification | [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) |
