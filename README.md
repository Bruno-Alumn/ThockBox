# Thockbox

[![Test](https://github.com/Bruno-Alumn/thockbox/actions/workflows/test.yml/badge.svg)](https://github.com/Bruno-Alumn/thockbox/actions/workflows/test.yml)

Mechanical-keyboard sounds for every keystroke on your Mac. Free, open
source, and small: a native app of about 1.9 MB that uses almost no CPU
when you're not typing.

<p align="center">
  <img src="docs/menu-bar.png" alt="Thockbox menu bar panel" width="280">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/settings.png" alt="Thockbox settings window" width="380">
</p>

## Features

**Sound**
- Seven switch sets: Cardboard, Cream, Holy Panda, Japanese Black, Milky
  Yellow, Oreo and Super Red
- Separate press and release sounds, with their own samples for Space,
  Return, Backspace and each row of the keyboard
- Slight random pitch on every key, so repeated keys don't sound identical
- Tone Pad: drag to make the sound darker or brighter, and lower or higher
- Keys pan left to right by where they sit on the keyboard
- Optional typewriter ding on Return and mouse click sounds

**Control**
- Turn sounds on or off with ⌘⌃K, or option-click the menu bar icon
- Volume with Soft, Balanced and Loud presets, separate from system volume
- Play through any output device, not just the system default
- Mute modifier keys or function keys
- Haptic tap on Force Touch trackpads
- AppleScript support

**Automation**
- Mute when the screen locks
- Mute after 1 to 60 minutes without typing
- Launch at login

## Menu bar and desktop window

Thockbox lives in the menu bar. Click the keyboard icon for the quick
settings: on/off, switch set, volume and today's keystroke count.

**Settings…** (⌘,) opens the full desktop window with everything else: the
Tone Pad, key options, automatic mute, output device and general settings.
While the window is open Thockbox also shows a Dock icon; close the window
and it goes back to living only in the menu bar. Opening Thockbox again from
Finder, Launchpad or Spotlight brings the window back.

## Install

Thockbox builds from source. You need macOS 13 or later and Xcode's
command-line tools.

```sh
git clone https://github.com/Bruno-Alumn/thockbox && cd thockbox
make            # builds dist/Thockbox.app
make run        # opens it
make zip        # dist/Thockbox-<version>.zip, ready to send to someone
```

Move `dist/Thockbox.app` to Applications to keep it.

### Accessibility permission

The first time you open Thockbox, macOS asks for **Accessibility** access
(System Settings → Privacy & Security → Accessibility). Thockbox needs it to
hear key presses. The settings window opens on first launch to walk you
through it.

> **After rebuilding:** the app is ad-hoc signed, and macOS ties the
> Accessibility grant to the exact build. A rebuilt app can show as allowed
> in System Settings but still not hear keys. Reset it and grant it again:
>
> ```sh
> tccutil reset Accessibility io.github.bruno-alumn.thockbox
> ```
>
> Signing with a real developer identity avoids this:
> `make bundle CODESIGN_ID="Apple Development: you@example.com"`.

## Privacy

Thockbox only listens for key presses so it can play a sound. It doesn't
record what you type, store it, or send anything anywhere: there's no
network code, analytics or tracking. The code that handles key events is
about 160 lines in [`KeyListener.swift`](Sources/Thockbox/KeyListener.swift)
if you want to check.

## Performance

Measured on an Apple Silicon Mac (`make bench`):

| | |
|---|---|
| Key press to sound rendered | about 5 ms, plus your output device's delay |
| CPU per key press | about 1 ms |
| CPU while idle | about 0.6% |
| App size | about 1.9 MB |

Bluetooth headphones add their own delay (AirPods: about 160 ms). For the
snappiest sound, use the built-in speakers or wired headphones.

## AppleScript

```applescript
tell application "Thockbox"
    set sounds enabled to false
    set sound pack to "cream" -- pack ID or display name
    set sound volume to 0.55 -- 0.0 through 1.0
end tell
```

## Sounds

The sound sets come from MIT-licensed sources,
[tplai/kbsim](https://github.com/tplai/kbsim) and
[mechvibes](https://github.com/hainguyents13/mechvibes); the ding and mouse
clicks are synthesized. See [ATTRIBUTION.md](ATTRIBUTION.md) for what each
set was recorded from. Rebuild them with `make sounds` (needs
[uv](https://docs.astral.sh/uv/)).

Recordings are trimmed when they load to remove room noise before and after
each click, so fast typing doesn't build up a background hiss.

### Adding your own switch set

Add a folder to `Resources/Sounds/<your-pack>/` with your samples and a
`pack.json`:

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

`default` is required. `space`, `enter`, `backspace` and `row0` to `row4`
(top row to bottom row) are optional and fall back to `default`. When a list
has several files, one is picked at random each time. WAV, MP3, CAF, AIFF and
M4A all work. Run `make bundle` afterwards. A pack with a broken `pack.json`
or no `default` sounds is skipped, and the reason is logged.

## Development

```sh
make test    # unit tests, then a smoke test that plays every pack
make bench   # CPU per key press and idle CPU; fails on a big regression
swift build  # debug build
```

CI runs the unit tests and builds the app on every push and pull request.
The smoke test needs a sound output device, so run `make test` locally
before sending changes.

How it fits together: `KeyListener` hears key events and passes them to
`AppState`, which holds the settings and decides what to play. `SoundEngine`
plays samples through an AVAudioEngine graph (8 voices, each with its own
pitch shifter, then an EQ for the Tone Pad). Samples are decoded into memory
when a pack loads, so playing a key is a single buffer schedule. The UI is
SwiftUI: `MenuView` for the menu bar and `SettingsView` for the window.

## Credits

Thockbox started as a fork of
[OpenKlack](https://github.com/amruth-sn/openklack) by Amruth Niranjan and
has since gone its own way. It's inspired by
[Klack](https://tryklack.com/); it isn't affiliated with or endorsed by Klack
or Henrik Ruscon. If you'd like the original, it's worth buying.

## License

MIT. See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md).
