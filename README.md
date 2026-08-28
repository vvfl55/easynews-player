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

## Features

- Easynews search with relevance / newest / largest sorting, and pagination beyond the 250-result page cap
- VLCKit playback: MKV, HEVC, AV1, AC3, E-AC3, DTS, embedded subtitles
- Audio and subtitle track switching
- Resume where you stopped, per file
- Lock screen and Control Center controls, with background audio
- Playback speed, double-tap to seek, swipe down to dismiss
- Recent searches
- Hand off to VLC or Infuse from a result's context menu
- Raw-JSON inspector for debugging Easynews field changes

## Known gaps

- **Picture-in-Picture** is not wired up. VLCKit 4 supports it, but it needs an
  AVPictureInPictureController backed by a sample-buffer display layer, which is
  a meaningful chunk of work.
- **No AirPlay video.** VLC does not expose native AirPlay for arbitrary codecs.
- **macOS has no keyboard shortcuts** yet (space to play/pause, arrows to seek).
- **The Mac app does not self-update.** Adding Sparkle with an appcast pointing
  at GitHub Releases would fix that.

## If the build fails

Almost certainly the VLCKit pin. `project.yml` pins `4.0.0-a22` from VideoLAN's own Swift Package. Note the hyphen — `4.0.0a22` without it does not exist and 404s. If VideoLAN cuts a newer alpha, bump `exactVersion`.

## License

VLCKit is LGPLv2.1. It's dynamically linked here, which the license permits for a closed app, but you must credit it and let users replace the library. The Mac target already carries the attribution in its Info.plist.
