# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

`BlackSharkBattery` is a small macOS menu bar app (no Dock icon) that shows the battery level and charging state of a Razer BlackShark V2 Pro wireless headset, read over HID from its 2.4 GHz dongle (USB `1532:0555`). It is a solo project, published at https://github.com/matej-basic/blackshark-battery. The app is ad-hoc signed and built from source only.

## Repository layout

- `blackshark_battery.py`: the Python reference implementation (hidapi). The Swift code is a port of it; compare against it with `-v`. Leave it and `requirements.txt` alone.
- `Sources/BatteryCore/`: the four output frames, the reply parser, the query sequence, the state model, the polling rules and every user-visible string. Foundation only.
- `Sources/BlackSharkBattery/`: the menu bar app (AppKit, IOKit HID). Declared in `Package.swift` under `#if os(macOS)`. `HIDTransport.swift` is the only file that opens the dongle and sends to it.
- `Tests/BatteryCoreTests/`: swift-testing tests for BatteryCore. The Command Line Tools have no XCTest.
- `build.sh`: checks the hardware safety rule, builds, assembles and ad-hoc signs `build/BlackSharkBattery.app`. `./build.sh install` copies it to `/Applications`.

## Common commands

```bash
swift build --build-tests && swift test   # BatteryCore tests (see the TestingMacros note below)
./build.sh                                # check, build and sign build/BlackSharkBattery.app
VERSION=0.2.0 ./build.sh                  # set the bundle version (default is in build.sh)
build/BlackSharkBattery.app/Contents/MacOS/BlackSharkBattery --status -v   # one read, frames on stderr
.venv/bin/python -I blackshark_battery.py -v                               # the reference, run after, not at the same time
```

## Conventions worth knowing

- English everywhere in the repo. No em dashes.
- Hardware safety rule: the app sends exactly four output reports, all 64 bytes with report ID 2, byte for byte as in the README's Protocol table: remote mode on, remote mode off, battery query (`0x03/0x21`), charging query (`0x03/0x2A`), in the script's wrap sequence. Never setters (EQ, sidetone, idle timer, do-not-disturb), firmware commands, guessed command IDs or feature reports, and no probes or experiments that send anything else. `Frame` has a private initializer and `Command` has exactly two cases; keep it that way. `HIDLink.send` takes a `Frame`, never raw bytes. `--listen` and `--device` send nothing.
- `IOHIDDeviceSetReport` appears exactly once, in `HIDTransport.swift`, with `kIOHIDReportTypeOutput`. `build.sh` greps for this and for feature reports before it builds. Do not write that function name in comments elsewhere.
- Behaviour that can be decided without hardware goes into `BatteryCore` with a test. The app target only wires it to AppKit and IOKit.
- Swift style is `swift format lint --strict -r Sources Tests` with the settings in `.swift-format` (4-space indent, 160 columns).
- With the Command Line Tools only, `swift test` on a clean `.build` can fail with a `TestingMacros` plugin error. Run `swift build --build-tests` first, then `swift test`. On the macOS 27 Command Line Tools that is not enough; pass `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` to both commands.
- Do not run `./build.sh install` while testing; it replaces the installed app and quits the running one.
- `CHANGELOG` has no file extension.
