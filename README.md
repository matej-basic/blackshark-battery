# blackshark-battery

Reads the battery level of a Razer BlackShark V2 Pro wireless headset on macOS
by talking to its 2.4 GHz USB dongle over HID. macOS does not report a battery
for this headset, and Razer Synapse is not needed.

```
$ .venv/bin/python -I blackshark_battery.py
battery: 75% (on battery)
```

Tested on macOS 27 (Apple Silicon) with the dongle behind a CalDigit TS5 Plus
dock. No sudo and no Input Monitoring permission were needed.

## Setup

```bash
/usr/bin/python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Usage

```bash
.venv/bin/python -I blackshark_battery.py            # battery and charging state
.venv/bin/python -I blackshark_battery.py -v         # also log every frame in hex on stderr
.venv/bin/python -I blackshark_battery.py --listen 30  # send nothing, print unsolicited input reports
```

If the headset is off or out of range the script exits with
`no battery reply (headset off or out of range?)`.

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
