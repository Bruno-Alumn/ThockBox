# Changelog

What changed for people using ThockBox. The full list of pull requests is
on each [release](https://github.com/Bruno-Alumn/ThockBox/releases).

## Unreleased

- Places are more dependable. ThockBox checks where your Mac is when it
  starts and each time it wakes, so it knows you've moved even if macOS
  didn't report the arrival. Adding a place keeps trying for up to 20
  seconds; it used to give up at the first failed attempt, which is
  common on a Mac.

- A vague location reading no longer flips a place to "not here" while
  you're still there, and Add Current Location waits for you to answer the
  Location prompt before its 20 seconds start.

- Shortcuts: starting to record a second shortcut ends the first recording
  (it used to keep swallowing key presses), and resetting the on/off
  shortcut clears another shortcut that had taken its keys.

- Play Anyway while music plays now holds when a second app makes a sound.

- "Paused by" a password field clears from the menu bar icon and Settings
  as soon as you type again.

## 1.11.5

- ThockBox is now signed with Apple's Developer ID and notarized by Apple,
  so a download opens with one click instead of a trip to System Settings.
  Updating from an earlier version asks once more for Accessibility access;
  ThockBox opens Settings to help. If you're on 1.11.3 or earlier, download
  this version from the website once; later updates install themselves.

- Muting by place works again. Turning on Use your location asks for
  Location access right away, the places list shows its Add Current Location
  button again (it was cut off, so there was no way to add a place), and
  each place has its own remove button. If Location Services is off or
  ThockBox isn't allowed, Settings says so and opens the right page.

## 1.11.4

- Groundwork for releases signed with Apple's Developer ID and notarized by
  Apple, so later downloads open without the "Open Anyway" step in System
  Settings. When that update arrives, ThockBox may ask once more for
  Accessibility access, and opens Settings to help you grant it.

## 1.11.3

- ThockBox opens again after importing settings or installing an update.
  It used to quit and stay closed until you opened it yourself.

- With sounds off, Turn Off For and Switch Set are grayed out in the menu,
  rather than opening lists of choices you can't pick.

- Recording a shortcut that another ThockBox shortcut already uses now
  says so, instead of asking for different modifier keys. The message also
  goes away once a shortcut is recorded or recording is cancelled.

- Activity's Today by Hour chart centers each hour label under its bar.
  The labels used to start at the bar, so 6 AM's typing looked like 5 AM's.

## 1.11.2

- Places keep working after ThockBox restarts (it used to wait until you
  crossed a place's edge), a place that macOS can't check is tried again,
  and adding a place gives up with a message instead of spinning forever.

- Fixes from a code review: Return in the welcome window's Try it field no
  longer opens System Settings, the welcome window no longer hides behind
  other apps when opened from Settings, menu bar apps you type into (like
  Raycast) count as the app you're in again, and renaming a place keeps
  Play Anyway.

- **Simpler Settings:** shorter notes, shown only for the options you've
  turned on, sets for specific apps at the bottom of the Sound page, and
  menu bar options shown only while the menu bar icon is.

- What's New marks every fix with the wrench icon, including the bold
  "Fixed on macOS 27" note.

- The update preview in Settings › General lists the changes in plain
  words, the same as What's New, instead of pull request titles.

## 1.11.1

- The Welcome and What's New windows open fully on screen instead of
  running under the Dock on shorter displays.

- More polish: failed exports and imports explain what went wrong (a
  failed daily counts export used to say nothing), buttons line up on the
  right as in System Settings, the Places list keeps names aligned and tells
  VoiceOver where you are, and clearer wording in a few places.

- Settings › General shows a green check mark when Accessibility access is
  allowed, like the Welcome window.

- The menu's volume slider no longer stays gray after sounds are turned
  off and back on.

## 1.11.0

- **Mute by place:** save places like the office or a library, and ThockBox
  stays quiet there, or plays only there. macOS watches the places and tells
  ThockBox only when you arrive or leave, so it uses no extra battery, and
  it asks for Location access only when you add a place. It works with the
  other mutes: a meeting still mutes, and Play Anyway plays through.

- **Fixed on macOS 27:** the volume slider and today's typing count are
  back in the menu bar menu.

- The Settings window's title shows the page you're on instead of
  "Untitled".

- Fixes from testing on macOS 27: the menu no longer offers to mute a
  system prompt (like "Mute in CoreLocationAgent") after one appears,
  Settings footers show in full instead of ending in "…", the Tone sliders
  line up, the sidebar shows ThockBox's whole status, and on first launch
  macOS's Accessibility prompt opens in front of the welcome window
  instead of hidden behind it. Shortcuts line up in one column, with a
  small clear button beside a set one, and Settings › General groups the
  menu bar options under their own heading.

- Polish across Settings, the menu and the welcome windows: clearer
  wording, shortcut buttons that line up, an icon for every listed app,
  Turn Off For dimmed rather than hidden while sounds are off, and better
  VoiceOver labels.

## 1.10.0

- **A Liquid Glass app icon** on macOS 26: the keycaps and sound waves
  redrawn as layers that pick up the system's glass, tinted and clear
  styles. macOS 13 to 15 keep the current icon.

- The Welcome and What's New windows match the new Settings window:
  colored icons beside each setting and each note, and a centered header.

- **A new Settings window**, laid out like System Settings: a sidebar of
  pages with colored icons and ThockBox's status at the top, in a wider,
  shorter window you can resize.

- **Get ThockBox Typing Stats** in Shortcuts: keystrokes today or in total,
  today's typing speed, or days in a row, for automations and widgets.

## 1.9.0

- **Today in the menu:** the menu bar menu shows today's keystrokes and
  typing speed under the status line.
- **Keys typed by other apps** (text expanders, password managers, remote
  control) can be left silent and uncounted: Settings › Keys.
- **Reset Accessibility access** from Settings › General › Help, for when
  ThockBox is switched on in System Settings but still can't hear keys.

## 1.8.1

- Fixed: Play Anyway no longer switches off other mutes (going idle still
  mutes), and a sleep doesn't carry it into the next night.
- Fixed: quiet hours follow time zone and clock changes, and the streak
  counts yesterday right after waking past midnight.
- Fixed: imported settings only bring shortcuts that meet the usual rule, and
  importing a set each day keeps the imported set for today.
- The menu's Turn Off For › Until Tomorrow Morning is now Until 8 AM.

## 1.8.0

- **Today by hour** in Settings › Activity: a chart of when you typed today.
- **Key releases** can be turned off (Settings › Keys) for just the press
  sound.

## 1.7.0

- **Play only in chosen apps** (Settings › Muting): turn the app list around
  so ThockBox plays only in those apps and stays quiet everywhere else.
- **Play Anyway** in the menu while ThockBox has muted itself: sounds play
  until that reason ends, and the next time it comes up it mutes again.

## 1.6.0

- **Volume up and down shortcuts** (Settings › Keys, none by default): 10%
  steps from anywhere.
- **Streak** in Settings › Activity: how many days in a row you've typed.

## 1.5.0

- **Turn Off For** in the menu: 15 minutes, 1 hour, 4 hours or until 8 am,
  instead of only an hour.
- **Quiet hours** (Settings › Muting): mute every day between two times,
  10 pm to 8 am unless you pick others.
- **Export and import settings** (Settings › General › Help): bring your
  setup to another Mac. Keystroke counts and things tied to this Mac
  (output devices, calendars) stay put.
- **A different set each day** (Settings › Sound, off by default): moves to
  the next switch set each new day.
- **Best day and daily average** in Settings › Activity, over the last 30
  days.

## 1.4.0

- **Typing speed in the menu bar** (Settings › General): today's words per
  minute beside the icon, alone or after the keystroke count.
- **A shortcut for the next switch set** (Settings › Keys, none by default),
  and a Next ThockBox Switch Set action in Shortcuts.

## 1.3.0

- **Typing speed** in Settings › Activity: today's words per minute, at five
  keystrokes a word, leaving out pauses.
- **Sets for specific apps** (Settings › Sound): give an app its own switch
  set, say a quieter one in Terminal. It plays while that app is in front;
  every other app plays your usual set.

## 1.2.4

- Fixed: head tracking now starts when AirPods connect after spatial audio
  is on, and faces ahead again when they disconnect.
- Fixed: an app whose name can't be read can be unchecked under Playing now.

## 1.2.3

- The menu names the app when one app's sound mutes ThockBox ("Muted while
  Spotify plays"), so you know what to uncheck under Playing now.
- **What's New covers skipped versions:** updating from 1.2.0 straight to a
  later version shows what every version in between added.

## 1.2.2

- **Spatial audio follows your head** with AirPods (Settings › Sound › Follow
  head movement): the keys stay in place when you turn your head. Needs
  macOS 14.

## 1.2.1

- **See and ignore what counts as playing sound.** With Mute while other apps
  play sound on, Settings › Muting lists the apps holding sound open now; uncheck
  one (a call app, a browser) to stop it muting ThockBox.
- Fixed: the "Hey Siri" listener counted as an app playing sound, so that
  mute could stay on with nothing playing.

## 1.2.0

- **Mute during calendar events,** from the calendars you choose. All-day,
  free and declined events don't count. ThockBox asks for Calendars access
  the first time.
- **Mute while sharing or recording the screen,** so a call's screen share
  doesn't carry your typing.
- **Mute while other apps play sound,** such as music and videos (macOS 14.2
  or later). Alerts don't count.
- **Mute while playing a game:** any app filed under Games, or installed by
  Steam.
- **Focus filters:** a Focus can turn sounds off or pick a switch set
  (System Settings › Focus › Focus Filters), and it goes back when the Focus
  ends. Settings › Muting is now grouped into Mute During and Mute When.
- **Spatial audio on headphones** (Settings › Sound): each key comes from
  its place around you. Speakers stay as they are.
- **Scrolling sounds** (Settings › Keys, off by default): a soft tick per
  notch, like a mouse wheel.
- **A volume slider in the menu bar menu,** like the system Sound menu.
- The volume sliders tap a Force Touch trackpad at every 10%, and the
  brightness and pitch sliders at their middle.
- **The menu bar icon dims while sounds are off,** and can show today's
  keystrokes beside it (Settings › General).
- **Choose what clicking the icon does:** open the menu, or turn sounds on
  or off. Control-click always opens the menu.
- **App icon style:** Color, Graphite, or Graphite while sounds are off.
- **What's New** opens once after an update, like this. Settings › General ›
  Help reopens it and the Welcome window, whose icon presses like a key.
- **Export daily keystroke counts** as a CSV from Settings › Activity.
- **AppleScript** can turn sounds off for a while (`set off until to
  (current date) + 30 * minutes`), turn mouse clicks, scroll sounds and the
  Return ding on and off, and set `mute after idle`.
- **Notify when the switch set changes** (Settings › General, off by
  default): a notification names the set a Focus, Shortcuts or AppleScript
  picked.
- **Clicking the menu bar icon opens the menu again.** In 1.1.2 a plain
  click often showed nothing, and only a Control-click opened it.
- **Safer updates:** ThockBox only installs an update signed with its own
  release certificate, and always checks GitHub for updates.

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
