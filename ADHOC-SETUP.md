# Ad Hoc OTA setup

Signs the app for a **full year** and lets you install updates wirelessly from a
link. Your Mac is needed once here, and once a year when the certificate
expires. It does **not** need to be running when you install.

No App Store Connect, no privacy manifest, no 90-day cycle, no Apple review.

Budget 30–40 minutes. Do the steps in order.

Team: **430 Years Church of God in Christ** (Organization).

---

## 1. Get the iPhone's UDID — 3 min

Plug the iPhone into the Mac, open **Finder**, select the device in the sidebar.
Click the line under the device name (where it says model and capacity) — it
cycles through details. Keep clicking until you see **UDID**, then right-click →
**Copy UDID**.

It's a 25- or 40-character string.

---

## 2. Register the device — 2 min

developer.apple.com/account → **Devices** → **+**

- Platform: iOS
- Device Name: `iPhone`
- Device ID (UDID): paste
- **Continue** → **Register**

You get 100 device registrations per product family per year.

---

## 3. Register the Bundle ID — 3 min

**Identifiers** → **+** → **App IDs** → **App**

- Description: `Easynews Player`
- Bundle ID: **Explicit** → `com.vvfl55.easynewsplayer`
- Capabilities: leave everything off. Background audio is an Info.plist key,
  not an entitlement.
- **Register**

---

## 4. Distribution certificate — 12 min, the fiddly step

**Create a signing request on the Mac:**

Keychain Access → menu **Keychain Access** → Certificate Assistant →
**Request a Certificate From a Certificate Authority**

- User Email: your Apple ID email
- Common Name: `Easynews Player Distribution`
- CA Email: blank
- Select **Saved to disk** → save the `.certSigningRequest`

**Create the certificate:**

developer.apple.com → **Certificates** → **+** → **Apple Distribution** →
upload the request → **Download** the `.cer` → **double-click it** to install.

> ⚠️ An Organization account is limited to **two** distribution certificates.
> If the church already has one another app depends on, do not revoke it —
> create a second, or coordinate first. Revoking breaks every build signed
> with it.

**Export it for CI:**

Keychain Access → **My Certificates** → find
`Apple Distribution: 430 Years Church of God in Christ` → **expand the
triangle** so the certificate *and* its private key are both selected →
right-click → **Export 2 items** → format **.p12** → save as `dist.p12` → set a
password you'll remember.

Exporting without the private key produces a file CI cannot sign with. The
triangle is the whole trick.

---

## 5. Ad Hoc provisioning profile — 3 min

developer.apple.com → **Profiles** → **+**

- Type: **Ad Hoc** (under Distribution — *not* App Store)
- App ID: the one from step 3
- Certificate: the one from step 4
- Devices: tick your iPhone
- Name: `Easynews Player Ad Hoc`
- **Download** the `.mobileprovision`

Also note your **Team ID**: Membership page, a 10-character string.

---

## 6. GitHub secrets — 8 min

Binary files need base64 encoding first. In Terminal, `cd` to where you saved
them:

```bash
base64 -i dist.p12 | pbcopy            # paste as BUILD_CERTIFICATE_BASE64
base64 -i *.mobileprovision | pbcopy   # paste as PROVISIONING_PROFILE_BASE64
```

Each command overwrites the clipboard, so paste one into GitHub before running
the next.

github.com/vvfl55/easynews-player → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**, four times:

| Secret name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | base64 of `dist.p12` |
| `P12_PASSWORD` | the password from step 4 |
| `PROVISIONING_PROFILE_BASE64` | base64 of the `.mobileprovision` |
| `APPLE_TEAM_ID` | Team ID from step 5 |

The workflow checks for these. Until they exist it skips Ad Hoc entirely and
keeps building the unsigned AltStore IPA, so nothing breaks in the meantime.

---

## 7. Enable GitHub Pages — 2 min

github.com/vvfl55/easynews-player → **Settings** → **Pages**

- Source: **Deploy from a branch**
- Branch: **gh-pages** / **(root)** → **Save**

The `gh-pages` branch is created by the first signed release, so if it isn't
listed yet, push a tag first and come back.

---

## 8. Install

Open **https://vvfl55.github.io/easynews-player/** in **Safari** on the iPhone
and tap Install.

Safari specifically — Chrome and other browsers cannot start an
`itms-services://` install.

Bookmark that page. Every future release updates it in place, so installing an
update is: open bookmark, tap Install. Nothing needs to be running anywhere.

---

## Maintenance

| What | When | Who |
|---|---|---|
| App updates | whenever tagged | automatic; you tap Install |
| Distribution certificate | yearly | you — repeat steps 4, 5, 6 |
| Provisioning profile | yearly, or when adding a device | you |
| Developer Program membership | yearly | Apple bills it |

## Troubleshooting

- **"Unable to Install"** — the device UDID isn't in the profile, or the
  profile expired. Regenerate it with the device ticked.
- **Nothing happens when tapping Install** — not Safari, or the page was
  served over HTTP. `itms-services://` requires HTTPS, which Pages provides.
- **"No signing certificate found" in CI** — the `.p12` was exported without
  its private key. Redo step 4's export with the triangle expanded.
- **Install works but the app won't open** — the certificate was revoked, or
  the profile's year is up.
