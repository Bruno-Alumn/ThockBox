<div align="center">

<img src="docs/logo.png" width="128" height="128" alt="ThockBox app icon">

# ThockBox

**Mechanical keyboard sounds for your Mac.**

A small, native menu bar app that plays a real switch recording on every key press.

<a href="https://github.com/Bruno-Alumn/ThockBox/releases/latest"><img src="https://img.shields.io/badge/Download_for_macOS-E8553A?style=for-the-badge&logo=apple&logoColor=white" alt="Download ThockBox for macOS" height="36"></a>

<a href="https://github.com/Bruno-Alumn/ThockBox/releases/latest"><img src="https://img.shields.io/github/v/release/Bruno-Alumn/ThockBox?style=flat-square&color=E8553A&label=release" alt="Latest release"></a>
<img src="https://img.shields.io/badge/macOS-13%2B-1f2937?style=flat-square&logo=apple&logoColor=white" alt="macOS 13 or later">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2774c8?style=flat-square" alt="MIT license"></a>
<a href="https://github.com/Bruno-Alumn/ThockBox/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/Bruno-Alumn/ThockBox/test.yml?style=flat-square&label=tests" alt="Tests"></a>

[Features](#features) · [Install](#install) · [Using ThockBox](#using-thockbox) · [Troubleshooting](#troubleshooting) · [Privacy](#privacy) · [Contribute](#contribute)

</div>

---

ThockBox sits in the menu bar and plays a switch sound for every key you
type. It ships with seven switch sets, with samples per keyboard row and
separate ones for Space, Return and Backspace. Most sets also have their own
release sounds. Keys are panned by their position on the keyboard and pitched
slightly differently each time, and fast bursts are struck a little lighter
than slow, deliberate presses, so typing sounds like a real board rather
than one sample on repeat. Every set plays at the same loudness, so switching
sets doesn't change the volume.

It began as a fork of [OpenKlack](https://github.com/amruth-sn/openklack) and
is inspired by [Klack](https://tryklack.com/). It is not affiliated with or
endorsed by Klack or its developer.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-dark.png">
    <img src="docs/screenshots/settings-light.png" width="520" alt="ThockBox settings window">
  </picture>
</div>

## Features

| Sound | Control | Automation |
|---|---|---|
| Seven switch sets, Mechvibes packs and your own recordings | ⌃⌘K (or your own shortcut) or option-click to toggle | Mute when the screen locks, during calls, or on speakers |
| Share your sets as a folder | Turn off for an hour, back on by itself | Turn off for a while from Shortcuts |
| Press and release samples (most sets) | Volume presets, remembered per output device | Mute after 1 to 60 minutes idle |
| Per-row samples, panned by key position | Choose any output device | Mute in apps you choose |
| Brightness and pitch controls | Mute modifier or function keys | Shortcuts and AppleScript |
| Random pitch variation | Haptic feedback on Force Touch trackpads | Launch at login |
| Optional Return ding and mouse clicks | Keystroke counts, with a chart of the last week | Updates from GitHub releases |

Switch sets: Cardboard, Cream, Holy Panda, Japanese Black, Milky Yellow,
Oreo and Super Red.

It is written in Swift with AppKit, SwiftUI and AVAudioEngine. It plays a key
press within about 5 ms and uses no CPU after 30 seconds without typing (see
**Performance** near the end).

## Install

1. Download `ThockBox-<version>.dmg` from the
   [latest release](https://github.com/Bruno-Alumn/ThockBox/releases/latest).
2. Open it and drag **ThockBox** to Applications.
3. Open it and grant the [Accessibility permission](#permissions) it asks for.

ThockBox needs macOS 13 or later. After that, it updates itself from new
releases.

> **A note about signing:** ThockBox isn't notarized by Apple, so the first
> time macOS asks whether to open it. Choose **Open**, or go to System
> Settings › Privacy & Security and click **Open Anyway**. Releases are signed
> with the same certificate every time, so the permission carries over to new
> versions.

Or install it with Homebrew:

```sh
brew install --cask bruno-alumn/thockbox/thockbox
```

## Using ThockBox

The menu bar icon opens a standard menu. Its first line says what
ThockBox is doing (playing, off, muted and why, or what needs fixing). When
something does, an item under it helps: **Open Accessibility Settings…**,
or **Why Is Sound Paused?** when another app's secure input is blocking key
presses. Then:

- **Sounds On**, checked while sounds play, and **Turn Off for an Hour**,
  after which sounds come back by themselves.
- **Switch** and **Volume** submenus.
- **Mute in** the app you were just using.
- **Update to** the new version, when there is one.
- **Settings…** (<kbd>⌘</kbd><kbd>,</kbd>) and **Quit ThockBox** (<kbd>⌘</kbd><kbd>Q</kbd>).

| Action | What it does |
|:--|:--|
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>K</kbd> (or your own shortcut) | Turn sounds on or off |
| <kbd>⌥</kbd>-click the menu bar icon | Turn sounds on or off |
| Click the menu bar icon | Open the menu |
| <kbd>⌘</kbd><kbd>,</kbd> | Open Settings |

The settings window is a standard Mac preferences window with five tabs:

- **Sound:** on and off, the switch set (including your own) with a field
  to try it, volume and output device, and tone (brightness, pitch and
  variation).
- **Keys:** the on/off shortcut, which keys play (and mouse clicks), and
  extras: the Return ding and a trackpad tap with each key.
- **Muting:** when ThockBox goes quiet by itself, and the apps it stays quiet
  in.
- **Activity:** keystrokes today, in total, and over the last week.
- **General:** login, the menu bar icon, updates and help.

While the window is open ThockBox appears in the Dock; closing it returns
ThockBox to the menu bar. Opening ThockBox from Finder, Launchpad or
Spotlight while it is running also brings up the window.

### Automatic mute

ThockBox can go quiet on its own and come back when the reason goes away:

- **During calls:** while another app uses the microphone (macOS 14.2 or
  later). "Hey Siri" and Voice Control are ignored, since they listen all
  the time.
- **When the screen locks.**
- **On speakers:** with "headphones only" on, keys play through headphones
  (wired, Bluetooth or USB) and stay quiet on the Mac's speakers, a display
  or AirPlay. Handy in an office or a shared room.
- **In muted apps:** while one of the apps you picked is in front.
- **After inactivity:** after 1 to 60 minutes without typing. The next key
  press wakes it.

The first line of the menu bar menu says which one is active.

### Your own switch sets

The quickest way is **Settings › Sound › Add Your Own…**, or dropping a
folder onto the switch list. Three kinds of folder work:

- **A Mechvibes sound pack** (a folder with a `config.json`, from
  [Mechvibes](https://github.com/hainguyents13/mechvibes) or its community).
  Both the current format, with press and release sounds for every key, and
  the older one are read. Each key's sound goes to its row, so a pack gives
  many different recordings per row.
- **A set exported from ThockBox**, or any folder with a `pack.json` (see
  **Custom switch sets** near the end). It's added as it is.
- **Your own recordings.** Files with *space*, *enter*/*return* or
  *backspace*/*delete* in the name play for those keys, files with *up* or
  *release* in the name play when a key is let go, and everything else plays
  for any key.

Added sets are converted into `~/Library/Application Support/ThockBox/Sounds/`,
so they survive updates. They get the same noise trimming and loudness
matching as the built-in sets. **Your Sets** in Settings › Sound can export
one as a folder to share (anyone can add it with Add Your Own, mapping and
all) or move it to the Trash.

### Shortcuts and AppleScript

ThockBox adds actions to the Shortcuts app: **Turn ThockBox Sounds On or
Off**, **Toggle ThockBox Sounds**, **Turn Off ThockBox Sounds for a While**,
**Set ThockBox Switch Set** and **Set ThockBox Volume**. Use them in a Focus automation (Work Focus → Holy Panda,
Sleep → off) or any shortcut. "Toggle ThockBox sounds" and "Change ThockBox
switches" also work from Spotlight and Siri with no setup.

<details>
<summary><strong>AppleScript</strong></summary>
<br>

```applescript
tell application "ThockBox"
    set sounds enabled to false
    set sound pack to "cream" -- pack ID or display name
    set sound volume to 0.55 -- 0.0 to 1.0
    set mute during calls to true
    set headphones only to true
    get mute reason -- e.g. "Muted in Safari.", or "" when not muted
    get keystrokes today
end tell
```

Read-only: `automatically muted`, `mute reason`, `off until` (when a timed
off ends, or `missing value`), `keystrokes today` and `keystrokes total`. The first time a script controls ThockBox, macOS asks
whether to allow it.

</details>

## Troubleshooting

<details>
<summary><strong>No sound at all</strong></summary>

Open the menu bar menu. Its first line says if Accessibility access is
missing, if sounds are muted automatically and why, or if another app's
secure input is blocking key presses. Also check that the toggle is on
(⌃⌘K by default) and the volume isn't at zero.
</details>

<details>
<summary><strong>Sound stops in some apps</strong></summary>

While a password field is focused, or while Terminal's Secure Keyboard Entry
is on, macOS doesn't pass key presses to other apps. That's expected. If it
stays that way after you leave the field, quit and reopen the app the menu
names. Also check Settings › Muting.
</details>

<details>
<summary><strong>Sound is late</strong></summary>

Bluetooth headphones add around 100 to 250 ms that no app can remove.
Settings › Sound › Output shows the delay for the current device. Built-in
speakers and wired headphones respond within a few milliseconds.
</details>

<details>
<summary><strong>Access was granted but nothing plays after rebuilding</strong></summary>

Builds made without the signing certificate get a new identity each time.
Run `make signing-cert` once, or reset the permission as shown under
**Build from source** under [Contribute](#contribute).
</details>

<details>
<summary><strong>Still stuck?</strong></summary>

Settings › General › Report a Problem… opens a new issue with your ThockBox
and macOS versions filled in.
</details>

## Privacy

ThockBox has no accounts, analytics or keystroke logging. It uses key events
only to choose and play a sound, and does not record, store or transmit what
you type. The code that receives key events is in
[`KeyListener.swift`](Sources/Thockbox/KeyListener.swift) and is short enough
to read in a few minutes.

Its only network request is a daily check with the GitHub API for the latest
release, which contains nothing but the app version. Turn it off in
Settings › General.

### Permissions

| Permission | Why it’s needed |
|:--|:--|
| **Accessibility** | Lets ThockBox receive key presses from other apps so it can play a sound for each one. On first launch a short welcome window asks for it, and lets you pick a switch set and try it while you wait. |

### Updates

When a newer release is out, the menu bar menu offers it, and Settings ›
General offers **Install and Relaunch**. ThockBox downloads the release's
disk image, checks that it holds a correctly signed ThockBox of that
version, replaces the installed copy and reopens. If that fails, **Download
from GitHub** opens the release page instead.

## Contribute

- **Found something broken?** Use **Settings › General › Report a Problem…**,
  or [open an issue](https://github.com/Bruno-Alumn/ThockBox/issues/new).
- **Want to help?** Fork the repository and open a pull request against `main`.
  Run `make test` locally first: CI can't run the smoke test, since it needs an
  audio output device.

Much of ThockBox was built with AI coding agents, then compiled, tested and
exercised on a real Mac before merging. AI-assisted contributions are welcome
on the same terms as any other: say what you changed and be honest about what
you tested.

<details>
<summary><strong>Build from source</strong></summary>
<br>

Building needs the Xcode command line tools.

```sh
git clone https://github.com/Bruno-Alumn/ThockBox.git
cd ThockBox
make            # build dist/ThockBox.app
make run        # open it
```

Copy `dist/ThockBox.app` to Applications to keep it. `make dmg` produces a
signed disk image, `dist/ThockBox-<version>.dmg`, for sharing.

macOS ties the Accessibility permission to how the app is signed. Run
`make signing-cert` once: it creates a self-signed "ThockBox Signing"
certificate in your login keychain, and every build after that is signed with
it, so you grant access once. Without it, builds are ad-hoc signed and each
rebuild needs the permission again:

```sh
tccutil reset Accessibility io.github.bruno-alumn.thockbox
```

You can also sign with a developer certificate:
`make bundle CODESIGN_ID="Apple Development: you@example.com"`.

```sh
make test          # unit tests, a smoke test that plays every pack, and a launch check
make bench         # CPU per key press and idle CPU (typing and paused), fails on a regression
make icon          # rebuild the app icon from art/logo-source.png
make sounds        # rebuild the bundled sound sets (requires uv)
make signing-cert  # one-time: create the certificate builds are signed with
make cask          # point packaging/thockbox.rb (the Homebrew cask) at this version's disk image
make dmg           # dist/ThockBox-<version>.dmg, the disk image people download
make release       # publish the disk image as a GitHub release (requires gh)
```

CI runs the unit tests and builds the app on every push and pull request.

**Architecture**

- `KeyListener` receives key and mouse events from AppKit.
- `AppState` holds the settings and decides what to play. Keystroke counts
  live in `StatsStore`.
- `SoundEngine` plays samples through AVAudioEngine: eight voices, each with
  its own pitch shifter, into an EQ for the tone controls. Samples are decoded
  into memory when a pack loads, so a key press is a single buffer schedule.
- The interface is SwiftUI: `MenuView` for the menu bar, `SettingsView` for
  the settings window. Both show `AppState.status`, so they always agree on
  what's happening.

</details>

<details>
<summary><strong>Custom switch sets</strong></summary>
<br>

For full control (per-row sounds, a gain trim), add a folder under
`Resources/Sounds/` with your samples and a `pack.json`, then run
`make bundle`.

```json
{
  "id": "my-pack",
  "name": "My Pack",
  "keys": {
    "default":   {"down": ["press/key1.wav", "press/key2.wav"], "up": ["release/key.wav"]},
    "space":     {"down": ["press/space.wav"], "up": ["release/space.wav"]},
    "enter":     {"down": ["press/enter.wav"]},
    "backspace": {"down": ["press/backspace.wav"]},
    "row0":      {"down": ["press/num_row.wav"]}
  }
}
```

- `default` is required. `space`, `enter`, `backspace` and `row0` to `row4`
  (top to bottom) are optional and fall back to `default`.
- When a list has several files, one is chosen at random for each key press.
- WAV, MP3, CAF, AIFF and M4A are supported.
- Room noise before and after each click is trimmed automatically when the
  pack loads.
- A pack with an invalid `pack.json` or no `default` sounds is skipped, and
  the reason is written to the log.

</details>

<details>
<summary><strong>Performance</strong></summary>
<br>

Measured on Apple Silicon with `make bench`:

| Metric | Value |
|---|---|
| Key press to rendered audio | ~5 ms, plus output device latency |
| CPU per key press | ~1 ms |
| CPU while typing | ~0.6% |
| CPU after 30 s without a key | 0% (the audio engine pauses; the next key adds ~8 ms) |
| Memory | ~26 MB (what Activity Monitor shows) |
| App size | ~2.6 MB |

`make test` also launches the built app and fails if its CPU or memory runs
away, and CI runs the same check on every pull request.

Bluetooth headphones add their own latency, around 160 ms for AirPods. Built-in
speakers or wired headphones give the most immediate response.

</details>

<details>
<summary><strong>Project documentation</strong></summary>
<br>

| Document | What’s inside |
|:--|:--|
| [Changelog](CHANGELOG.md) | What changed in each version |
| [Attribution](ATTRIBUTION.md) | Where each switch set's recordings come from |

</details>

---

ThockBox began as a fork of [OpenKlack](https://github.com/amruth-sn/openklack)
by Amruth Niranjan. The switch recordings come from
[tplai/kbsim](https://github.com/tplai/kbsim) and
[mechvibes](https://github.com/hainguyents13/mechvibes), both MIT licensed.

**MIT License:** OpenKlack © 2026 Amruth Niranjan and contributors; ThockBox
changes © 2026 Bruno-Alumn. See [LICENSE](LICENSE) and
[ATTRIBUTION.md](ATTRIBUTION.md).

<sub>More Mac apps by Bruno-Alumn: [SolStream](https://github.com/Bruno-Alumn/SolStream) · [Tuckaway](https://github.com/Bruno-Alumn/Tuckaway)</sub>
