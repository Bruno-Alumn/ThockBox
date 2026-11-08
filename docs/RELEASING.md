# Releasing ThockBox

## Steps

1. In one PR, bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist` and rename `## Unreleased` in `CHANGELOG.md` to
   `## <version>`. The What's New window shows the section whose heading
   matches the version. Merge it.
2. On an up-to-date `main`, run `make release` (Developer ID signing and
   notarization; see below). This builds and signs
   the app, makes the disk image, updates `packaging/thockbox.rb`, and
   publishes `v<version>` on GitHub with that version's changelog section as
   the release notes.
3. Land the cask's new version and checksum through a PR.
4. Copy `packaging/thockbox.rb` to `Casks/thockbox.rb` in
   `Bruno-Alumn/homebrew-thockbox`, then commit and push.
5. Check it: the downloaded disk image's sha256 matches the cask, and
   releases/latest lists `ThockBox-<version>.dmg`.

## Signing

Two identities can sign a release:

- **ThockBox Signing**, a self-signed certificate in the login keychain
  (`make signing-cert`). Releases up to 1.11.4 were signed with it
  (`SIGNING=thockbox`).
- **Developer ID Application: Bruno Cassina (22R95V8NA5)**
  (`SIGNING=developer-id`, the default since 1.11.5). These builds are also
  notarized by Apple and stapled, so macOS opens them without the "Open
  Anyway" step.

Whichever identity signs the build, it carries the same designated requirement
from `packaging/designated_requirement.txt`, and that requirement accepts
either one:

```
identifier "io.github.bruno-alumn.thockbox" and (
    certificate leaf = H"bf187bb3…"              ← ThockBox Signing
    or (anchor apple generic and … leaf[subject.OU] = "22R95V8NA5")  ← Developer ID
)
```

Two things depend on that requirement:

- **Permissions.** macOS keeps a granted permission (Accessibility, Location,
  Calendars) for any later build that meets the requirement recorded when it
  was granted.
- **Updates.** The in-app updater only installs a download that meets the
  running app's own requirement (`Updater.satisfiesOwnRequirement`).

`scripts/sign_app.sh` signs with the hardened runtime and
`packaging/ThockBox.entitlements`, which lists the protected resources the
hardened runtime would otherwise block: Location (muting at places) and
Calendars (muting during meetings). If a feature starts using another
protected resource (microphone input, camera, contacts, Apple Events sent to
other apps), add its entitlement there or that feature silently stops working.

### Notarization

`make dmg SIGNING=developer-id` and `make release SIGNING=developer-id`
notarize twice with `scripts/notarize.sh`: first the app, so its ticket is
stapled to the copy inside the disk image, then the disk image. They use the
notarytool keychain profile `tuckaway-notary` (override with
`NOTARY_PROFILE=…`), which holds the Apple ID login for team 22R95V8NA5. To
set it up on another Mac:

```sh
xcrun notarytool store-credentials tuckaway-notary --apple-id <apple id> --team-id 22R95V8NA5
```

It prompts for an app-specific password. Never put that password in the repo
or in a command line.

A submission that isn't accepted stops the build. Read Apple's reason with
`xcrun notarytool log <submission id> --keychain-profile tuckaway-notary`.

### Moving from ThockBox Signing to Developer ID

Installed copies up to 1.11.3 have the old requirement, which names only the
ThockBox Signing certificate. Their updater would refuse a Developer ID build.
So the move takes two releases, in this order:

1. **Bridge release:** `make release`, signed with ThockBox Signing but
   carrying the combined requirement. Every installed copy accepts it (it's
   the same certificate), and from then on each copy runs with the combined
   requirement and can update to a Developer ID build.
2. **Developer ID releases,** from 1.11.5 on.

Done: 1.11.4 was the bridge release (2026-11-07) and 1.11.5 the first
Developer ID release (2026-11-08). Copies on 1.11.3 or older can't update to
1.11.5 by themselves (their updater refuses it) and need one manual download.

**One re-grant is unavoidable for older permissions.** macOS stores the
requirement in force *when a permission was granted*, and running a newer
build doesn't update it. A permission granted under 1.11.3 or earlier names
only the ThockBox Signing certificate, so the first Developer ID build loses
it. A permission granted under the bridge release or later carries over.
Tested in a VM (2026-11-07): Accessibility granted under 1.11.3 was lost on
the Developer ID build, and Calendars granted under the bridge build was
kept.

The updater handles this. It compares the download's signing certificate
with the running app's, and when they differ (the first Developer ID update)
it resets the stale Accessibility grant and opens Settings after relaunch,
so ThockBox asks for access cleanly rather than looking broken. This logic
has to ship in the bridge release, since the bridge's updater is the one that
installs the first Developer ID build. Location and Calendars simply ask
again the next time they're needed.

Keep a backup of the ThockBox Signing certificate (Keychain Access → export).
Until every release is signed with the Developer ID, losing it would mean one
more round of re-granting for everyone.
