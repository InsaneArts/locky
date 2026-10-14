# Security

Locky draws its own lock screen over your session. While it shows, the macOS lock screen is not on: the
session behind Locky's windows stays unlocked. This page says what Locky does about that, and what it
cannot do.

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
  Unlock › Keep the keyboard on the lock screen), it takes the keys with an event tap for the rest of the lock.
  Without it, Locky switches to the macOS lock screen. It switches too when another app has secure keyboard
  entry on (Terminal's Secure Keyboard Entry, a focused password field), which hides the keys from any event
  tap.
- **No injected code.** Locky.app and the guard are signed with the hardened runtime, so
  `DYLD_INSERT_LIBRARIES` cannot load code into them.
- **Other launches are ignored.** While a lock is on, Locky ignores requests from another launch, such as
  `Locky window` or `Locky preview`.
- **No menu commands during a lock.** Locky removes its menus, the Services menu included, while a lock is on,
  so none of its menu shortcuts work until you unlock.

## What Locky does not do

- **FileVault and the login window stay Apple's.** Locky does not replace the login window or FileVault's
  unlock at startup. Disk encryption is FileVault's job.
- **Keep macOS's own screen lock on.** If macOS also asks for your password after the display turns off, you may
  unlock twice after a long lock. Leave it on anyway: it protects the Mac whenever Locky is not running.
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
