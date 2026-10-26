# blackshark-battery

Shows the battery level of a Razer BlackShark V2 Pro wireless headset on macOS
by talking to its 2.4 GHz USB dongle over HID. macOS does not report a battery
for this headset, and Razer Synapse is not needed.

There are two ways to use it. `BlackSharkBattery` is a small menu bar app with
no Dock icon that shows the level and the charging state. It needs macOS 14 or
later and has been built and tested on Apple silicon only.
`blackshark_battery.py` is the Python script the app was ported from; it stays
as the reference implementation.

```
$ .venv/bin/python -I blackshark_battery.py
battery: 75% (on battery)
```

Tested on macOS 27 (Apple Silicon) with the dongle behind a CalDigit TS5 Plus
dock. No sudo and no Input Monitoring permission were needed.

## Install

You need the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

    ./build.sh

This compiles the Swift package in release mode and produces
`build/BlackSharkBattery.app`, signed ad hoc. Start it with
`open build/BlackSharkBattery.app`. To copy it to `/Applications` (quitting a
running copy first), run:

    ./build.sh install

`VERSION=x.y.z ./build.sh` puts a different version number in the app.

## Uninstall

Untick "Launch at login" in the menu first if you turned it on. Then:

    pkill -x BlackSharkBattery
    rm -rf /Applications/BlackSharkBattery.app
    defaults delete com.matejbasic.BlackSharkBattery

## Features

- A headphones icon in the menu bar with the level next to it, for example
  `74%`. A bolt follows the number while the headset charges. The icon is a
  headphones glyph rather than a battery so it is not mistaken for the Mac's
  own battery.
- With the headset off or out of range the icon is greyed out and has no
  number. Without the dongle it changes to a crossed-out headphones glyph. If
  the dongle cannot be opened, or answers with a value above 100, the number
  is replaced by `!` and the menu says why.
- The menu shows the state ("Battery 74%, on battery", "Charging, 74%",
  "Headset off or out of range", "Dongle not connected") and when it was
  read ("Updated 14:05"). With the headset off it shows the last good reading
  instead ("Last reading 74% at 14:05"), also after a relaunch.
- "Refresh now" (Cmd-R), "Launch at login" and "Quit" (Cmd-Q).
- The headset is read every 5 minutes, every 2 minutes while it charges, 1.5
  seconds after the dongle is plugged in, 5 seconds after the Mac wakes, and
  when you open the menu if the last read is older than a minute. Razer rates
  the headset at up to 70 hours, about 1.4 percent per hour, so polling more
  often would not change the number. If the dongle is busy or cannot be
  opened, the app tries again after 20 seconds, up to three times in a row,
  then goes back to the normal interval. For testing, the interval can be
  shortened (to no less than 30 seconds) with
  `defaults write com.matejbasic.BlackSharkBattery pollIntervalSeconds -float 30`.

## Command line options

Run the binary inside the app, for example
`build/BlackSharkBattery.app/Contents/MacOS/BlackSharkBattery --status`.

- `--status` reads the headset once and prints the same line as the Python
  script, `battery: 74% (on battery)`, `(charging)` or `(unknown)`. Without a
  dongle or a reply it prints the script's error message on stderr and exits
  with 1.
- `--listen SECONDS` opens the dongle, sends nothing, and prints every input
  report that arrives in that time.
- `--device` prints what the app knows about the dongle without opening it:
  its location, primary usage page, usage pairs, whether it carries the
  `RequiresTCCAuthorization` property, and whether this process has the Input
  Monitoring permission (`granted`, `denied` or `unknown`; only read, never
  requested).
- `-v`, anywhere on the line, logs every frame in hex on stderr in the
  script's format. On its own it starts the menu bar app with frame logging,
  which then shows up in Console.app.

## How it works

The dongle is one HID device in IORegistry with two usage pairs, consumer
control (`0x0C/0x01`) and the vendor channel (`0xFF00/0x01`). Its primary usage
page is the consumer one, so the app matches on the usage pairs
(`kIOHIDDeviceUsagePageKey`), not on the primary page. hidapi lists the same
device twice, once per pair, which is why the script can filter on
`usage_page == 0xFF00`. The app watches for the dongle with IOKit's HID manager
without opening it, in `Sources/BlackSharkBattery/DongleMonitor.swift`.

For each read the app opens the dongle with `kIOHIDOptionsTypeNone`, runs the
battery and charging queries, and closes it again. Nothing stays open between
reads. hidapi opens the device exclusively; the app opens it without
exclusive access. The volume keys on the headset are therefore expected to
keep working during a read, but that has not been tested. Input Monitoring is not
expected to be needed: macOS asks for it only for devices that carry the
`RequiresTCCAuthorization` property, and this dongle does not (the built-in
keyboard and a Logitech receiver on the same Mac do). The app never calls
`IOHIDRequestAccess`. If the permission were ever denied, the menu says so.
This code is in `Sources/BlackSharkBattery/HIDTransport.swift`, the only file
that sends anything to the device.

Every query is wrapped the same way as in the script (see Protocol below), and
the app sends only those four frames. A successful read is 8 output reports
and takes about 0.3 seconds; with the headset off the battery query is tried
three times, the charging query is skipped, and the read gives up after about
1.1 seconds.

One deliberate difference from the script: a battery value above 100 is
reported as a bad reply ("Unexpected battery value") instead of being shown.
The script would print it as it is.

The frames, the reply parser, the query sequence, the polling rules and every
string the app shows are in the `BatteryCore` library, `Sources/BatteryCore/`.
It uses Foundation only and has unit tests (see Development).

## Python reference script

### Setup

```bash
/usr/bin/python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### Usage

```bash
.venv/bin/python -I blackshark_battery.py            # battery and charging state
.venv/bin/python -I blackshark_battery.py -v         # also log every frame in hex on stderr
.venv/bin/python -I blackshark_battery.py --listen 30  # send nothing, print unsolicited input reports
```

If the headset is off or out of range the script exits with
`no battery reply (headset off or out of range?)`.

hidapi opens the dongle exclusively. Do not run the script while the app is in
the middle of a read; the app then reports the dongle as busy and tries again
after 20 seconds, up to three times. If the fourth read in a row also fails,
it goes back to the normal 5-minute interval.

## Device

Dongle: "Razer BlackShark V2 Pro 2.4", USB `1532:0555`.

USB interfaces 0 to 2 are audio. Interface 3 is the only HID interface and
carries two top-level collections:

| Usage page | Usage | Report ID | Purpose |
|---|---|---|---|
| `0x000C` | `0x01` | 1 | Consumer controls (volume, mute), 1-byte input |
| `0xFF00` | `0x01` | 2 | Vendor channel, 63-byte input and output (64 with report ID) |

There are no feature reports, which is why IORegistry shows
`MaxFeatureReportSize = 1`. Everything below goes over the vendor collection.

Raw report descriptor:

```
050c0901a10185011500250109cd09b509b609b77501950481021500250109b009b109b309b4
7501950481221500250109e909ea09e2750195038122750595018101c00600ff0901a1018502
150026ff0009027508953f8102150026ff0009037508953f9102c0
```

## Protocol

Output frames are 64 bytes, zero-padded. Bytes not listed are `00`.

| Frame | Bytes |
|---|---|
| Remote mode on | `02 80 07 00 00 50 41 0e 00 02 e1 01` |
| Remote mode off | `02 80 07 00 00 50 41 0e 00 02 e1 00` |
| Battery query | `02 80 08 00 00 50 41 08 00 03 21 00` |
| Charging query | `02 80 08 00 00 50 41 08 00 03 2a 00` |

A query is wrapped in remote mode, the same way Synapse does it: one extra
"remote on" to wake the radio link, then "remote on", the query, and "remote
off". The script sends nothing else.

Replies start with `02 0e 50 49`. Counting from the report ID at byte 0:

- byte 12: echo of the command (`0x21` or `0x2a`)
- byte 13: `01` for ACK
- byte 14: payload length
- byte 15: value. Battery is 0 to 100; charging is `00` on battery, non-zero
  while charging.

Example battery reply, `0x4b` = 75%:

```
02 0e 50 49 08 ce 2d 83 03 00 04 00 21 01 01 4b ...
```

The dongle also sends status frames starting `02 0d 50 49 01 c0`, which the
script skips. A 30-second passive listen produced a single unsolicited report
and it was not a battery frame, so the battery has to be queried.

## Sources

- OpenRazer PR #2862, "Add support for the Razer BlackShark V2 Pro 2.4
  (1532:0555)", `driver/razerblackshark_driver.c`. Open, not merged as of
  2026-10-26. The frame layout there comes from Synapse USB captures.
  https://github.com/openrazer/openrazer/pull/2862
- HaloBattery, `providers/blackshark.py` (MIT), commit `2251f05`. Same frames;
  the wake-up sequence in this script follows it.
  https://github.com/HeyOkay/HaloBattery/blob/main/providers/blackshark.py
- HeadsetControl does not support this headset, and Homebrew has no formula
  for it.

## Not tried

The OpenRazer driver defines setters for EQ, sidetone, do-not-disturb and the
idle timer. None of them have been sent from this repo.

## Development

    swift build --build-tests
    swift test

With the Command Line Tools alone, `swift test` from a clean checkout can fail
with `plugin for module 'TestingMacros' not found`. Run
`swift build --build-tests` once first; after that `swift test` works. With the
Command Line Tools for macOS 27 even that is not enough, and both commands need
the plugin path passed explicitly:

    P=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
    swift build --build-tests -Xswiftc -plugin-path -Xswiftc $P
    swift test -Xswiftc -plugin-path -Xswiftc $P

Before it builds, `build.sh` checks that `IOHIDDeviceSetReport` appears exactly
once in `Sources`, in `HIDTransport.swift`, and that nothing uses feature
reports or element writes. The build stops if either check fails.

Swift style follows `.swift-format` (4-space indent, 160 columns):
`swift format lint --strict -r Sources Tests`.

## Quit

Click the menu bar icon and choose Quit, or run `pkill -x BlackSharkBattery`.

## License

MIT, see [LICENSE](LICENSE).
