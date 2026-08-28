# TestFlight setup

Everything here needs a human signed in to Apple. Once it's done, releases
upload themselves and TestFlight pushes them to your phone.

Budget 45–60 minutes. Do it in order; later steps depend on earlier ones.

Team: **430 Years Church of God in Christ** (Organization).

---

## 1. Register the Bundle ID — 5 min

developer.apple.com/account → **Certificates, Identifiers & Profiles** →
**Identifiers** → **+**

- Type: **App IDs** → **App**
- Description: `Easynews Player`
- Bundle ID: **Explicit** → `com.vvfl55.easynewsplayer`
- Capabilities: leave all off. Background audio is an Info.plist key, not an
  entitlement, so nothing to enable here.
- **Register**

---

## 2. Create the app record — 5 min

appstoreconnect.apple.com → **Apps** → **+** → **New App**

- Platform: **iOS**
- Name: must be unique across the whole App Store, so `Easynews Player` may be
  taken. Anything works — try `Easynews Player VV`. Only you will see it.
- Primary Language: English
- Bundle ID: pick the one from step 1
- SKU: any string, e.g. `easynews-player`
- User Access: **Full Access**

The app stays in "Prepare for Submission" forever. You are never submitting it.

---

## 3. Distribution certificate — 15 min, the fiddly one

**First, a Certificate Signing Request on the Mac:**

Keychain Access → menu **Keychain Access** → Certificate Assistant →
**Request a Certificate From a Certificate Authority**

- User Email: your Apple ID email
- Common Name: `Easynews Player Distribution`
- CA Email: leave blank
- Select **Saved to disk**
- Save as `CertificateSigningRequest.certSigningRequest`

**Then create the certificate:**

developer.apple.com → **Certificates** → **+**

- Type: **Apple Distribution**
- Upload the `.certSigningRequest` file
- **Download** the resulting `.cer`, then **double-click it** to install into
  your login Keychain

> ⚠️ Organizations get a limited number of distribution certificates. If the
> church already has one in use by someone else, **do not revoke it** — create
> an additional one if the quota allows, or coordinate first. Revoking a
> certificate breaks every build signed with it.

**Then export it for CI:**

In Keychain Access → **My Certificates** → find `Apple Distribution: 430 Years
Church of God in Christ` → expand the triangle so both the certificate **and**
its private key are selected → right-click → **Export 2 items** →
format **.p12** → save as `dist.p12` → set a password and remember it.

Exporting without the private key produces a file CI cannot use. The triangle
matters.

---

## 4. Provisioning profile — 5 min

developer.apple.com → **Profiles** → **+**

- Type: **App Store Connect** (under Distribution)
- App ID: the one from step 1
- Certificate: the one from step 3
- Name: `Easynews Player App Store`
- **Download** the `.mobileprovision`

---

## 5. App Store Connect API key — 5 min

appstoreconnect.apple.com → **Users and Access** → **Integrations** tab →
**App Store Connect API** → **+**

- Name: `GitHub Actions`
- Access: **App Manager**
- **Download** the `.p8`

> ⚠️ The `.p8` downloads exactly once and can never be retrieved again. If you
> lose it, revoke the key and make a new one.

Note down two values from that page:
- **Key ID** — next to the key, e.g. `A1B2C3D4E5`
- **Issuer ID** — above the key list, a long UUID

Also grab your **Team ID**: developer.apple.com → Membership → a 10-character
string like `AB12CD34EF`.

---

## 6. GitHub secrets — 10 min

The binary files have to be base64 encoded first. In Terminal, `cd` to wherever
you saved them:

```bash
base64 -i dist.p12 | pbcopy                      # then paste as BUILD_CERTIFICATE_BASE64
base64 -i *.mobileprovision | pbcopy             # then paste as PROVISIONING_PROFILE_BASE64
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy         # then paste as APP_STORE_CONNECT_KEY_BASE64
```

Each command copies to the clipboard; paste it into GitHub before running the
next one, or you'll overwrite it.

github.com/vvfl55/easynews-player → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**, seven times:

| Secret name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | base64 of `dist.p12` |
| `P12_PASSWORD` | the password you set in step 3 |
| `PROVISIONING_PROFILE_BASE64` | base64 of the `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_BASE64` | base64 of the `.p8` |
| `APP_STORE_CONNECT_KEY_ID` | the Key ID from step 5 |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID from step 5 |
| `APPLE_TEAM_ID` | the Team ID from step 5 |

---

## 7. Add yourself as an internal tester — 2 min

App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** →
create a group → add your Apple ID.

Internal testers skip Beta App Review entirely, so builds appear minutes after
upload. Install the **TestFlight** app on the iPhone and enable **Automatic
Updates** in its settings.

---

## 8. Tell Claude it's done

The pipeline gets written after the secrets exist, so it can be tested against
something real rather than guessed at.

---

## Maintenance

| What | When | Who |
|---|---|---|
| Build refresh | every 90 days | automatic, scheduled in CI |
| Distribution certificate | yearly | you — repeat steps 3, 4, 6 |
| Developer Program membership | yearly | you — Apple bills it |

CI will warn when the certificate is within 30 days of expiring.

## If something breaks

- **"No signing certificate found"** — the `.p12` was exported without its
  private key. Redo the export with the triangle expanded.
- **"Invalid provisioning profile"** — the profile does not match the
  certificate or bundle ID. Regenerate it after the certificate, not before.
- **Upload rejected for the build number** — every upload needs a unique build
  number. CI handles this by using the run number.
