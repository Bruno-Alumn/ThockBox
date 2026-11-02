# Changelog

What changed for people using ThockBox. The full list of pull requests is
on each [release](https://github.com/Bruno-Alumn/ThockBox/releases).

## Unreleased

- **Choose what clicking the menu bar icon does** (Settings › General):
  open the menu, or turn sounds on or off. Control-click always opens the
  menu.
- Fixed: **Mute during calendar events** didn't work after ThockBox
  restarted until the switch was turned off and on.
- Fixed: a Focus that turned sounds off could leave them off for good if
  ThockBox restarted during it. A Focus that only picks a set no longer turns
  sounds on.
- **Export daily keystroke counts** as a CSV from Settings › Activity.
- **AppleScript** can turn mouse clicks, scroll sounds and the Return ding
  on and off.
- **App icon style** (Settings › General): Color, Graphite, or Graphite
  while sounds are off, for the Dock and ThockBox's windows.
- **Safer updates:** ThockBox only installs an update signed with its own
  release certificate, not just any valid signature, and release builds
  always check GitHub for updates.
- The volume slider taps the trackpad at every 10%, and the brightness and
  pitch sliders at their middle (Force Touch trackpads).
- **Scrolling sounds** (Settings › Keys, off by default): a soft tick per
  notch, like a mouse wheel, and a trackpad tap with it when the trackpad
  tap is on.
- **What's New** opens once after an update with the notes for that
  version. Settings › General › Help reopens it, and the Welcome window.
- **Notify when the switch set changes** (Settings › General, off by
  default): a notification says which set a Focus, Shortcuts or AppleScript
  picked.
- **Mute while playing a game** (Settings › Muting): any app filed under
  Games, or installed by Steam.
- **Mute while other apps play sound** (Settings → Muting): music, videos
  and games quiet the keys; alerts don't. Needs macOS 14.2 or later.
- **Focus filter:** turn sounds off, or pick a switch set, while a Focus is on
  (System Settings › Focus › Focus Filters). It goes back when the Focus ends.
- The ThockBox icon in the Welcome window presses like a key.
- **The menu bar icon dims while sounds are off,** so it's easy to tell at a
  glance. Turn it off in Settings › General.
- **Today's keystrokes in the menu bar,** next to the icon, if you turn it
  on in Settings › General.
- **AppleScript can turn sounds off for a while:** `set off until to (current
  date) + 30 * minutes`. Setting it to `missing value` turns sounds back on.
- **Mute during calendar events** (Settings › Muting). ThockBox asks for
  Calendars access the first time; all-day, free and declined events don't
  count. Choose which calendars count, for example to
  leave out a shared family calendar.
- **Mute while sharing or recording the screen** (Settings › Muting), so a
  call's screen share doesn't carry your typing.
- **Clicking the menu bar icon opens the menu again.** In 1.1.2 a plain
  click often showed nothing and only a Control-click opened it.

## 1.1.2

- **Turn Off for an Hour** in the menu bar menu: sounds come back by
  themselves, even if ThockBox is restarted in between. The menu and
  Settings say until when.
  Shortcuts has a matching action, **Turn Off ThockBox Sounds for a While**.
  AppleScript can read when it ends (`off until`).
- **Share your switch sets.** Settings → Sound → Your Sets → Export… saves a
  set you added as a folder, named in a standard save panel. Anyone can add
  it with Add Your Own, with its key mapping intact.
- **"Why Is Sound Paused?"** in the menu explains when another app's secure
  input is blocking key presses, and what to do about it.
- **VoiceOver** reads the settings properly: brightness and pitch as
  "30% brighter" or "20% lower", volume as a percentage, the shortcut as
  "Control Command K", labels on the muted-app buttons, and each bar of the
  week chart as "Monday, 1,234 keystrokes".
- **AppleScript** can turn "headphones only" and "mute when locked" on and
  off.
- **Sets removed in Finder** drop out of the menu the next time it opens,
  and sound falls back to Cream instead of going silent.
- **Report a Problem…** in Settings → General opens a new GitHub issue with
  your ThockBox and macOS versions filled in, and nothing else.
- **Adding a shared set** whose sound files are missing or broken now says
  which file is the problem, instead of adding a set that plays nothing.
  Recordings with the same name from several folders are all kept. Error
  alerts have a short title, with the reason underneath.
- **Mechvibes packs** that name a sound file they don't include now import,
  with those keys using the pack's other sounds. Before, the whole import
  failed with a message blaming the audio format.
- **Check Now** says what went wrong when it fails: no internet, GitHub
  rate-limiting your network, or GitHub being down, instead of always
  "Couldn't reach GitHub".
- **Muted apps** show their real names ("Safari", not "Safari.app"), and
  the Delete key removes the selected ones.
- **The menu bar icon** shows "off" whenever keys make no sound, including
  while Accessibility access is missing or another app's secure input is
  blocking key presses. It used to look on in those cases.
- **Settings** reopens on the tab you used last and where you left the
  window.
- **An output device you picked** (USB or Bluetooth headphones, say) gets
  the sound back when it's reconnected. It used to stay on the speakers
  until you picked the device again.
  While it's unplugged, Settings lists it as "Not Connected" instead of
  showing a blank.
- **The on/off shortcut** can't be set to something that clashes any more:
  it needs ⌃, or ⌘ with ⌥. ⌘C or ⌥E used to toggle sounds on every copy or
  accent as well, and Settings now says what works instead of just beeping.
  The shortcut is now a system hotkey, so the app in front no longer gets
  the key press as well.
- **System Default** follows the system's output again after you've
  picked another device in Settings: plugging in headphones used to leave
  sound on the speakers.
- **Sound recovers** if the audio engine can't restart right away, say on
  wake while Bluetooth audio is still connecting; it used to stay silent
  until sounds were turned off and on.
- **Install and Relaunch** no longer freezes ThockBox for a few seconds
  while it checks the download.
- **Turning sounds on with the shortcut** no longer clicks when you let go
  of ⌃ and ⌘.
- **Settings keeps its Dock icon** when the welcome window is closed while
  it's open (and the other way round), and the volume menu always shows a
  checkmark.

## 1.1.1

- Downloads are a disk image: open it and drag ThockBox to Applications.
- The in-app updater installs from disk images. If you have 1.1.0, update
  to 1.1.1 by hand once. Later updates install from the menu.

## 1.1.0

The first downloadable release, also available with
`brew install --cask bruno-alumn/thockbox/thockbox`.

**Sound**
- Every switch set plays at the same loudness, so switching sets doesn't
  change the volume.
- Add your own switch sets: Mechvibes sound packs, or a folder of your own
  recordings.
- Keys in a fast burst are struck slightly lighter than slow presses.
- Keys on ISO (European) and JIS (Japanese) keyboards play from the right
  row.
- Each output device remembers its own volume.

**Muting**
- Mute during calls and recordings, when the screen locks, after a period
  without typing, in apps you choose, or on speakers (headphones only).
- The menu says why sounds are muted when they are.

**Interface**
- A standard menu bar menu and a standard settings window with Sound,
  Keys, Muting, Activity and General tabs.
- A welcome window on first launch, and a field to try sounds before
  choosing.
- A custom on/off shortcut, and an option to hide the menu bar icon.
- A chart of keystrokes over the last week.

**Automation**
- Shortcuts actions: turn sounds on or off, set the switch set, set the
  volume. They work in Focus automations, Spotlight and Siri.
- More AppleScript properties: call mute, mute state and keystroke counts.

**Under the hood**
- The audio engine pauses after 30 seconds without a key, so ThockBox uses
  no CPU while you're not typing.
- Accessibility access carries over to updates.
- Updates show what's new, and offer the download page if they can't
  install.

## 1.0.0

The first version of ThockBox, built from source: a menu bar app that plays
real switch recordings as you type, with seven switch sets, per-row
sounds, release sounds, a tone control and AppleScript support.
