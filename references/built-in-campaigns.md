# Built-in campaigns — ship campaigns inside the app build

**Amply SDK {{SDK_VERSION}}+** (iOS, Android, KMP, React Native / Expo). Older SDKs ignore the file — shipping it does no harm.

A campaign marked **Built-in** ships inside the app binary as `amply-bundle.json`. On an install that has **never** received campaigns from Amply, the SDK shows the built-in campaigns from that file — Mini-app screens and images included — with no internet. The first successful download from Amply replaces the bundle **for good**; from then on the app uses its saved copy of the live campaigns offline, as before, and does not read the bundle again (the one exception is an emergency switch-back by Amply — see *What happens on the device*).

No app code. No secret. One CLI command per release, one committed file per platform.

## When to suggest it

Suggest Built-in when the app must show a campaign on its **very first launch**, and that launch may be offline or on a slow network:

| Fits | Why |
|---|---|
| **Onboarding** (Mini-app story or full screen, trigger `SessionStarted`, `on 1`) | The first session is the one that matters, and it may start on a plane or behind a captive Wi-Fi page. |
| **First-launch paywall / intro offer** | Without a bundle, a user who opens the app offline never sees the offer on launch 1. |
| **Consent / terms / privacy notice** built as a Mini-app | Must be there before anything else; cannot wait for a download. |

**Don't** suggest it for campaigns that can wait for the first connection (winback, rating asks, seasonal offers, anything triggered days in) — they gain nothing and every release then needs a re-bundle. A campaign **running an A/B test is never bundled**; don't plan a built-in A/B test.

In the Phase 4 audit, add a `Built-in?` row to the campaign's *What* block: `yes — first-launch onboarding` or `no`.

## Turning it on

- **Admin:** the **Built-in** switch on the campaign form's first step, below the type tiles. A **Built-in** badge marks it in the campaign list.
- **MCP:** `built_in: true` on `campaign_create`, or on `campaign_update`. `campaign_update` is a full replace that **returns the campaign to Draft** — on a live campaign that takes it off air until it is activated again, so say so before you send it (or have the user flip the switch in the admin). Unlike other fields, `built_in` left out on `campaign_update` stays as it is. `campaign_get` / `campaigns_list` return `built_in`.

What gets bundled: campaigns that are **Built-in AND active AND not running an A/B test**. A draft or stopped campaign is left out even with the flag on.

## Bundling it into the app — the CLI

Run it **yourself** in the app repository root (per the SKILL.md *Build & verify yourself* contract), with the **public** keys from `amplyApps` (Phase 1b) — one per shipped platform, never the secret:

```bash
npx @amplytools/cli bundle --android <android apiKeyPublic> --ios <ios apiKeyPublic>
```

Either flag alone is fine. The first run writes `amply.json` (public keys + output paths, no secrets — **commit it**); every later run is just:

```bash
npx @amplytools/cli bundle
```

Node ≥ 18. Re-running with nothing changed in Amply prints "up to date" and leaves the files **byte-for-byte untouched** (no diff). The download time and CLI version inside the file are not counted as changes.

### Where the file lands — per platform / RN flavour

| Project | What the CLI writes | One-time extra step |
|---|---|---|
| **Android (native, KMP)** | `app/src/main/assets/amply-bundle.json` (the module that applies `com.android.application`) | None — Gradle packages `assets/` automatically. Several app modules → pass `--out-android <module>/src/main/assets`. |
| **iOS (native, KMP `iosApp`)** | `amply-bundle.json` in the folder holding the app target's `Info.plist` | **Add it to the app target once** (below). Several app targets / not found → `--out-ios <folder>`. |
| **RN Flavour A (Pure Bare)** and **B (Bare + Expo Modules)** | `android/app/src/main/assets/amply-bundle.json` and `ios/<App>/amply-bundle.json` | iOS: add to the app target once. **No `app.json` plugin entry** — no prebuild runs in A/B, so the plugin never executes. |
| **RN Flavour C (Expo Prebuild)** and **D (Expo Managed)** | `amply-bundle.android.json` + `amply-bundle.ios.json` in the project root, next to `app.json` | **The Amply config plugin must be in the active Expo config** (`app.json`, or `app.config.js` / `.ts` when the project uses one): append `"@amplytools/react-native-amply-sdk"` to `expo.plugins` if absent, keeping every existing entry. At `expo prebuild` (local, or EAS in the cloud) it copies both files into the native projects and registers the iOS one as a target resource. No Xcode step. |

The name inside the app is fixed: `amply-bundle.json` — the SDK looks for no other name and takes no setting. The CLI only warns when an `--out-*` path names the file differently, so never rename it.

**Flavour C trap.** The CLI picks Expo mode only when `ios/` **and** `android/` are absent or listed in `.gitignore` (`/ios`, `/android` — Expo's template does this). If they exist on disk and are not ignored, it treats the project as bare RN and writes **into** them — and the next `expo prebuild --clean` throws the files away. Fix the `.gitignore` first, then run the CLI.

### iOS: add the file to the app target (once)

The CLI never edits the Xcode project. It reads it, and warns on every run (and `--check` fails) while `amply-bundle.json` is not a resource of any app target.

- **Synchronized folder** (default for projects created in Xcode 16+; `PBXFileSystemSynchronizedRootGroup` in the `.pbxproj`): nothing to do — the file is in the target already.
- **Classic groups:** the human drags the file into the app's group in Xcode and ticks the app target under **Add to targets** (it then appears in **Build Phases → Copy Bundle Resources**). This is an Xcode-UI step — hand it to the human in one line, then **verify yourself** with `npx @amplytools/cli bundle --check` (exit `0` = in the target and up to date). Do not hand-edit `project.pbxproj` to do it.

### Commit

Commit the bundle file(s) **and** `amply.json`. Never put the `apiKeySecret` anywhere near this flow — the CLI doesn't take one.

## Keeping it current

A bundle is a snapshot. **Re-run the CLI before every release build** — say so in the hand-off. Edits made in Amply after the snapshot reach a never-online device only on its first connection.

**CI gate** (pin the version so CI never runs an unreviewed CLI release):

```bash
npx @amplytools/cli@1.0.0 bundle --check
```

Exit `1` when the committed bundle differs from what Amply publishes now (ignoring download time and CLI version), or when the iOS file is not in a target. GitHub Actions: `actions/setup-node@v4` with `node-version: 20`, then the line above. `--json` prints a machine-readable summary.

Adding a CI step is a change to the team's pipeline: in `interactive`, offer it and add it on a yes; in `autopilot`, don't edit CI — put the exact step in the audit as a recommendation.

## What happens on the device

- **Never online →** built-in campaigns from the bundle, screens included.
- **First successful download →** live campaigns replace the bundle for good.
- **Frozen version.** Until that first download, the device shows each built-in campaign as it was when the CLI ran — including a campaign stopped in Amply since.
- **Impressions and frequency limits** are keyed by the same campaign id, so they count the same and carry over when the live campaigns arrive ("once per device" holds across the switch).
- **One key.** A bundle made for another public key is ignored entirely. Good: a dev bundle never shows in a prod build. Trap: a debug build that initializes with a **different** (dev) Amply application's key shows **nothing** from a bundle made with the prod key. Bundle with the key the shipped build uses; test with that key too.
- **Damaged or oversized bundle →** ignored as a whole, one warning log, never a crash, never delays SDK readiness.
- An Amply operator can switch an app back to its bundle in an emergency (support-side; nothing for the app to do).

Limit: **20 MB** for the whole file. Over that, the CLI refuses (exit `4`) and writes nothing — fewer built-in campaigns or lighter images.

## Verifying it

1. **What will be bundled** — with the MCP connected, `builtin_bundle_get(application_id)` (one call per application; iOS and Android are separate applications). Per key: `status` (`published` / `not_published_yet` / `unreadable`), `generated_at`, `stale` (Amply's live config was rewritten after the published bundle — it may lag), `campaigns` (what the bundle will hold), `object_count` / `object_bytes` (Mini-app files, each counted once), `problems`, `missing` (flagged built-in but absent, with `reason`: `not_active`, `running_experiment`, `failed_to_compile`, `not_published_yet`) and `cli.command` / `cli.npx_command` / `cli.output_paths` — the exact command to run. Run this **before** the CLI and report every `missing` entry with its reason. Activating a campaign or ending an A/B test makes changes real users see — do it only on the user's explicit go (`campaign_activate` needs its own permission anyway).
2. **File is right** — `npx @amplytools/cli bundle --check` exits `0`.
3. **On a test device or simulator** — never a personal phone without asking: uninstalling erases the app's data. Uninstall the app (it must never have reached Amply), install the new build, go offline, launch, fire the trigger. The campaign shows; a system-events listener sees `ConfigFetchFinished` with `configSource: "bundle"` and `bundleGeneratedAt`. Android emulator: `adb uninstall <package>`, install, `adb shell cmd connectivity airplane-mode enable`, launch (`… airplane-mode disable` after). iOS: the simulator shares the Mac's network, so the offline check is a **physical device in airplane mode** — a human step ("UI work needs eyes"). Online, the live campaigns win (`configSource: "network"`), which proves nothing about the bundle.

`ConfigFetchFinished.configSource` (SDK {{SDK_VERSION}}+): `network` | `cache` | `bundle` | `forcedBundle` | `empty`. From the same version `success` means only "this download validated" — it is `false` after a fallback, where older SDKs reported `true`.

## CLI exit codes

| Code | Meaning | Do |
|---|---|---|
| `0` | Written, or `--check` up to date | Commit. |
| `1` | `--check`: bundle out of date, or iOS file not in a target | Re-run `npx @amplytools/cli bundle`, commit; add the iOS file to the target. |
| `2` | Usage or local file problem (bad flag, unreadable `amply.json`, path not found / not writable, path outside the project) | Read the message; pass `--out-android` / `--out-ios`. |
| `3` | Network / HTTP error | Retry. |
| `4` | Integrity: a file failed its checksum or size, a file is missing, the data is for another key, or the bundle would exceed 20 MB | Retry once; if it persists, report to Amply support. Over 20 MB: trim. |
| `5` | Nothing published for this key yet | Check it's the right app's **public** key; then save any campaign of that app in Amply and re-run. |
| `70` | Internal CLI bug | Report to Amply support. Never treat as drift. |

A download, validation or staging error leaves the existing files untouched — every platform is downloaded and verified, and every file staged, before anything is replaced. Each file is then replaced atomically.

## Common mistakes

| Mistake | Fix |
|---|---|
| Removing `"@amplytools/react-native-amply-sdk"` from `app.json` (or `app.config.*`) → `expo.plugins` in an Expo (C/D) app, or replacing the whole `plugins` array to add it. | Keep it, and add it by appending — it is what copies the bundle files in at prebuild. Without bundle files it changes nothing. |
| Adding the plugin entry in Flavour A/B to "make the bundle work". | No prebuild runs there; the CLI writes straight into `android/` and `ios/`. |
| Forgetting the iOS target membership. | The file sits in the folder but not in the `.app`. `--check` must exit `0`. |
| Bundling with the secret key, or with a dev application's key for the prod build. | Public key of the application the shipped build initializes with. |
| Not re-running before a release. | Never-online users of that build see the stale snapshot. Add the CI `--check` gate. |
| Marking a campaign Built-in and expecting it in the bundle while it is a draft, stopped, or under an A/B test. | `builtin_bundle_get` → `missing[].reason` says which. |
| `campaign_update` with `built_in: true` on a live campaign without warning the user. | It returns the campaign to Draft — off air until re-activated. |
| Expecting an edit or a stop in Amply to reach devices that have never been online. | They see the build's snapshot until their first successful download. |
| Running the CLI in Flavour C with un-ignored `ios/` / `android/` folders. | It writes into them and `prebuild --clean` wipes the files. Ignore the folders first. |
