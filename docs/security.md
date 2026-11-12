# Security

Locky draws its own lock screen over your session. While it shows, the macOS lock screen is not on: the
session behind Locky's windows stays unlocked. This page says what Locky does about that, and what it
cannot do.

## If something goes wrong

- If Locky crashes, hangs, or is killed during a lock, a second process shows the macOS lock screen within 8 seconds.
- On the lock screen, press ⌃⌥⌘Q to switch to the macOS lock screen.
- Locky unlocks only with your login password or Touch ID, never after a time.

The Welcome's last page says the same. The sections below give the details.

## What Locky guarantees

- **No unlock without you.** Only Touch ID or your login password ends a lock. Nothing opens it after a
  time.
- **A crash, a hang, or a kill locks the Mac.** Each lock starts `locky-guard`, a second process in a session
  of its own. Locky writes it a heartbeat every second from its main thread. If Locky exits during a lock
  without saying the lock ended, the guard locks the Mac with the macOS lock screen. If no heartbeat comes
  for 8 seconds, the guard locks the Mac and then ends Locky, so a frozen shield does not stay after you
  unlock macOS. If the guard exits during a lock, or does not start, Locky switches to the macOS lock screen.
  Each switch keeps Locky's lock up until the macOS lock screen is up, so the desktop does not show between
  the two.
- **⌃⌥⌘Q switches to the macOS lock screen.** It is the way out when something goes wrong, and it never
  lets anyone in. The lock screen names it after the third wrong password, or when one password check takes
  more than 5 seconds, and Settings › General names it under Unlock. `"emergency_exit": false` in settings.json
  turns it off.
- **No lock without the keyboard.** If Locky is not the active app with its lock window key within 1.5
  seconds of a lock, or loses the keyboard during a lock and does not get it back within 1 second, it does
  not stay up, since typing would go to the app behind it. With Accessibility access (Settings › General ›
  Accessibility), it takes the keys with an event tap for the rest of the lock.
  Without it, Locky switches to the macOS lock screen. It switches too when another app has secure keyboard
  entry on (Terminal's Secure Keyboard Entry, a focused password field), which hides the keys from any event
  tap.
- **Nothing shows above the lock.** macOS draws some windows above every app's, Locky's lock included, such as
  "Allow accessory to connect?" when a keyboard is plugged in. Anyone at the Mac could answer one, so within a
  second Locky switches to the macOS lock screen, which keeps such prompts until you unlock.
- **Every key goes to the password field.** The field has the keyboard from the lock's first frame, also while it is
  hidden (a theme that shows it on activity, or the ambient mode). If anything takes the keyboard from it, the next key gives it back
  before its character lands, and so does a click anywhere on the lock. While the event tap holds the keys, Locky asks
  for the keyboard again each second, so the field shows its caret again when the other app is gone. After a wake, or
  when the screen saver ends, Locky asks for the keyboard and restarts Touch ID. The field is disabled only while a
  password check runs and during the wait after wrong passwords.
- **Nothing covers the lock while you are away.** During a lock, Locky holds a power assertion
  (`PreventUserIdleDisplaySleep`), as a video player does. Idle display sleep and the screen saver then do not start
  over the lock: before, the screen saver drew over Locky's windows and took the keyboard and Touch ID while it
  showed. Locky turns the displays off itself instead (settings.json's `display_off`, or the system's display sleep
  time; see [settings.md](settings.md#keys)), and after `ambient_after` seconds without input it shows only the theme's
  background. A closed lid and system sleep still sleep the Mac. Locky releases the assertion when the lock ends, and
  macOS releases it if Locky exits. The screen saver can still start from a hot corner: when it ends, Locky takes the
  keyboard and Touch ID back.
- **The Touch ID button locks the Mac.** With Settings › General › Lock with the Touch ID button on, a press of
  the Touch ID button shows Locky's lock instead of the macOS lock screen. This needs Accessibility access: Locky
  stops the press before macOS sees it, with an event tap. It stops only that one event, and passes every other
  event on. It does not stop the press when Locky is not running, during a Locky lock (macOS then locks over
  Locky, and you unlock twice), or while its tap is off: without Accessibility, with the switch off, or when
  macOS turns the tap off because Locky did not answer in time. Then the button shows the macOS lock screen, as
  before. If Locky's lock is not up within 2 seconds of a press it stopped, Locky switches to the macOS lock
  screen.
- **No injected code.** Locky.app and the guard are signed with the hardened runtime, so
  `DYLD_INSERT_LIBRARIES` cannot load code into them.
- **Other launches are ignored.** While a lock is on, Locky ignores requests from another launch, such as
  `Locky window` or `Locky preview`.
- **No menu commands during a lock.** Locky removes its menus, the Services menu included, while a lock is on,
  so none of its menu shortcuts work until you unlock.

## What Locky asks macOS for

Locky asks for each permission where it is used, with a line that says why. The Welcome's second page and
Settings › General show Accessibility and Login Items the same way. Each row shows its state: Grant, or Granted
with a green check.

- **Accessibility.** The Touch ID button's tap and the keyboard's event tap need it (see above). Locky asks for it on
  the Welcome's second page and in Settings › General, just before Lock with the Touch ID button. That switch
  waits for it. Grant opens System Settings › Privacy & Security › Accessibility (Device Control and Data Access
  from macOS 27), with a small panel under the System Settings window: drag Locky from the panel into the list.
  When Locky has the permission, the panel closes and Locky comes to the front.
- **Camera.** Only for Settings › General › Unlock › Take a photo. When you choose a number of wrong passwords,
  macOS asks once. If you said no, Grant opens System Settings › Privacy & Security › Camera. The lock never asks:
  without the permission, it takes no photo.
- **Login item.** Open at login adds Locky to System Settings › General › Login Items. If you switch it off there,
  the row says so, and Grant opens Login Items.
- **Location Services.** Only for a weather widget's Current Location. macOS asks once, when you pick Current
  Location in Customize; Grant in the row under Location asks too. If you said no, Grant opens System Settings ›
  Privacy & Security › Location Services. The lock never asks. With the permission, Locky takes a fix when it
  starts and as each lock starts, and keeps the last one in `~/Library/Caches/Locky/location.json`. Without it, the
  weather follows the city of the Mac's time zone. The coordinates go to Open-Meteo, for the weather, and to Apple,
  for the city's name.

Showing a state never asks: Locky reads it with `AXIsProcessTrusted()`, `AVCaptureDevice.authorizationStatus`,
`CLLocationManager.authorizationStatus`, and `SMAppService`. It reads the states again when you come back to Locky. While the panel is open, it reads
Accessibility once a second, for 5 minutes at most, and stops when Locky has it. A lock closes the panel at its
start, and no panel opens during a lock.

macOS ties a permission to the app's signature. A build signed ad hoc is a new app to macOS each time, so an old
Locky entry can stay on in the Accessibility list while the new build does not have the permission. Remove old
Locky entries with the − button, then grant it again. See the README's Build section.

### The one dependency

The rows, the panel, and the System Settings links come from
[PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) (MIT), Locky's only package dependency. Package.swift
pins it to version 2.11.3 exactly, and Package.resolved pins its commit (`cb96db4`). Locky links its
`PermissionFlow`, `PermissionFlowCameraStatus`, and `SystemSettingsKit` products. Their source was read before it
was added: they make no network calls, collect nothing, start no processes, and write no files. They use only
public APIs: Accessibility and window lists to follow the System Settings window, the `x-apple.systempreferences:`
URLs, and the drag pasteboard. PermissionFlow asks for Accessibility itself only when its
`promptForAccessibilityTrust` option is on, and Locky leaves it off. Its translated button words ship in
`Locky.app/Contents/Resources/PermissionFlow_PermissionFlow.bundle`; `locky health` says if they are missing.

## What Locky does not do

- **FileVault and the login window stay Apple's.** Locky does not replace the login window or FileVault's
  unlock at startup. Disk encryption is FileVault's job.
- **Locky does not change macOS's own password setting.** If macOS also asks for your password after the
  display turns off, you may unlock twice after a long lock. Keep that setting on anyway: it protects the Mac
  whenever Locky is not running.
- **Plugins are code that runs as you.** Like Neovim plugins, they can read your files and run programs.
  The limits in [plugins.md](plugins.md#the-rules-that-keep-the-lock-screen-safe) stop bugs from breaking
  the lock screen; they are not a sandbox against a hostile plugin. Install only plugins you trust.
- **Code that runs as you can still open it.** A program that kills or stops Locky and its guard at the same
  instant leaves the session open. A program running as you can do much worse already, so Locky does not
  defend against it.
- **Physical attacks are out of scope.** Someone with the Mac in hand and time can attack the hardware or
  the disk. FileVault and a firmware password are the defense there.

## Report a vulnerability

Report it privately, not in a public issue: use the GitHub repository's Security tab › Report a
vulnerability. Say what you did, what happened, and the macOS and Locky versions.
