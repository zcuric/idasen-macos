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
