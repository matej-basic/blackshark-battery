# Security policy

## Reporting a problem

Please report security problems privately, through the repository's Security tab ("Report a vulnerability"), not in a public issue. I will answer there. This is a one-person project, so a reply can take a few days.

Useful things to include: what you found, the version (`defaults read /Applications/BlackSharkBattery.app/Contents/Info.plist CFBundleShortVersionString`), your macOS version, and steps to reproduce.

## Supported versions

Only the latest release gets fixes. Until the first release (`v0.1.0`) is published, that means the current `main` branch.

## What to expect from the builds

The app is signed ad hoc and is not notarized by Apple. The one-line installer and the Homebrew cask remove the quarantine flag, so Gatekeeper does not check the app on first launch. Each release has a `SHA256SUMS` file, and the cask pins the sha256 of the zip. Both come from the same GitHub repository as the zip, so they detect a broken or swapped download but cannot protect against someone who controls the repository or its release workflow. If that matters to you, build from source with `./build.sh`.

## What the app does with your USB devices

The app opens one USB HID device, the BlackShark V2 Pro 2.4 GHz dongle (`1532:0555`), once per read, and closes it again. It sends that device only the four query frames listed in the README's Protocol table: remote mode on, remote mode off, the battery query and the charging query. It never sends setters, firmware commands or feature reports. `Frame` has a private initializer, so the code cannot build any other frame; `build.sh` refuses to build if the one output report call moves or a feature report call appears; and the unit tests check that every read sends nothing outside those four frames. It does not ask for Input Monitoring and has no network code. These checks cover the source in this repository. A malicious build could talk to the headset and to other HID devices in any way macOS allows a user process, and `SHA256SUMS` cannot tell you whether a build is malicious, only whether you got the file the release published.

The latest security review is in [docs/SECURITY-REVIEW.md](docs/SECURITY-REVIEW.md).
