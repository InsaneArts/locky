# Release

A release is a notarized Locky.app in a zip, with the update feed (`appcast.xml`) beside it on a GitHub release.
Locky's updater, `install.sh`, and the Homebrew cask all read from that release.

## Make one

1. Raise `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`. Sparkle offers a release only if its build number
   is higher than the installed one's.
2. Write the notes in `releases/<version>.md`. Sparkle shows them in its update window, and the GitHub release
   uses them.
3. Commit both.
4. Run `Scripts/release.sh`. It runs the tests, builds a universal app, signs it with the Developer ID, sends it to
   Apple for notarization, staples it, and writes `dist/Locky-<version>.zip` and `dist/appcast.xml`. It publishes
   nothing.
5. Run `Scripts/release.sh --publish`. It does step 4 again, then tags the commit, pushes `main` and the tag,
   creates the GitHub release with the zip and the feed, and writes the cask to
   [InsaneArts/homebrew-tap](https://github.com/InsaneArts/homebrew-tap) from `Scripts/locky.rb`.

The script needs, on the Mac that makes the release:

- the Developer ID certificate in the Keychain (`SIGN_IDENTITY`),
- a notarytool keychain profile (`NOTARY_PROFILE`, default `camus-notary`),
- the Sparkle key (below), and
- `gh`, signed in with push access to both repositories.

## The Sparkle key

The private key was created on Nov 13, 2026 with `generate_keys --account Locky` and lives only in the login
Keychain of the Mac that makes releases. Its public half is `SPARKLE_PUBLIC_KEY` in `Scripts/package_app.sh`, which
writes it to the app's Info.plist. Every installed Locky trusts only updates signed with this key. Without the
private key no later update can be signed, and people would have to install Locky again by hand. Export it once and
keep it in a password manager:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account Locky -x locky-sparkle-key.txt
```

`release.sh` stops if the Keychain's key does not match the public key in the built app.

## What reads the release

- **Locky.** `SUFeedURL` is `https://github.com/InsaneArts/locky/releases/latest/download/appcast.xml`. Sparkle
  checks it once a day, and Locky › Check for Updates… checks at once.
- **install.sh.** `curl … | sh` reads the same feed and installs the zip it lists first. It accepts the app only if
  `codesign` and Gatekeeper pass and the Team ID matches `TEAM_ID`, which is the same in `install.sh` and
  `release.sh`. To test it against another feed, set `LOCKY_FEED`; `LOCKY_INSTALL_DIR` picks the folder.
- **Homebrew.** `brew install --cask insanearts/tap/locky` downloads the zip by its version and checks its SHA-256.
  The cask says `auto_updates true`, so `brew upgrade` leaves Locky to its own updater.
