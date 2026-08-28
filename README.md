# Easynews Player

Search Easynews and stream the results with VLC's decoder. One SwiftUI codebase, two targets: iPhone/iPad and Mac.

VLCKit is embedded, so MKV containers, HEVC, AV1, AC3/E-AC3, DTS, FLAC and embedded subtitles all play natively — none of which AVPlayer will touch. Files stream over HTTPS range requests, so seeking works without downloading first.

## One-time setup

You need no Mac. Everything builds on GitHub's macOS runners.

1. Create a new repo and push these files to `main`.
2. The bundle ID is already set to `com.vvfl55.easynewsplayer` in `project.yml` and the workflow.
3. Go to **Settings → Actions → General → Workflow permissions** and select **Read and write permissions**. The workflow needs this to publish releases.

That's it. No certificates, no provisioning profiles, no secrets.

## Building

Push a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow generates the Xcode project with XcodeGen, builds both targets, and publishes a Release containing `EasynewsPlayer.ipa` and `EasynewsPlayer-macOS.zip`.

Pushes to `main` build too, but only tags cut a release. The first run takes 15–20 minutes because VLCKit's universal XCFramework is about a gigabyte; after that it's cached and runs take 3–5 minutes.

## Installing on iPhone/iPad

The IPA is **unsigned on purpose**. AltStore and SideStore re-sign with your own Apple ID at install time, which is why CI needs no certificate from you.

For updates without touching a computer again, add this as a source in AltStore:

```
https://raw.githubusercontent.com/OWNER/REPO/main/altstore-source.json
```

Replace `OWNER/REPO` with yours. Every tagged release regenerates that file, AltStore notices the new version, and you update with one tap.

Free Apple ID: the app expires every 7 days and needs a refresh. Paid developer account ($99/yr): it lasts a year.

## Installing on Mac

Unzip and drag to Applications. The build is ad-hoc signed, so Gatekeeper will complain the first time — right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/EasynewsPlayer.app
```

## Using it

Enter your Easynews username and password on first launch. They go to the Keychain and are sent only to `members.easynews.com`. Search, tap a result, it streams.

## If results look wrong

Easynews returns objects keyed by numeric strings (`"0"` is the hash, `"10"` is the filename) and shuffles them between API versions. The client decodes defensively — unknown fields degrade to `nil` instead of throwing — but if titles or sizes render blank, **long-press a row → Inspect raw JSON** to see exactly what came back, then adjust the key lists in `EasynewsFile.from()`.

The search parameters live in `EasynewsClient.request(query:page:credentials:)`. It uses the V2 endpoint, which returns up to 250 results per page.

## Known gaps

- **No audio/subtitle track picker yet.** VLCKit 4's track API differs from 3's, and I left it out so the first build goes green rather than failing on an API mismatch you can't debug without Xcode. Add it once you have a working IPA — `VLCMediaPlayer` exposes the tracks.
- **No pagination.** One page, 250 results.
- **Picture-in-Picture** is available in VLCKit 4 but not wired up.

## If the build fails

Almost certainly the VLCKit pin. `project.yml` pins `4.0.0-a22` from VideoLAN's own Swift Package. Note the hyphen — `4.0.0a22` without it does not exist and 404s. If VideoLAN cuts a newer alpha, bump `exactVersion`.

## License

VLCKit is LGPLv2.1. It's dynamically linked here, which the license permits for a closed app, but you must credit it and let users replace the library. The Mac target already carries the attribution in its Info.plist.
