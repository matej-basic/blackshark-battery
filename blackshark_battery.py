#!/usr/bin/env python3
"""Read battery level of a Razer BlackShark V2 Pro 2.4 (USB 1532:0555) over HID.

Protocol ("PA"/MXIC frames on vendor page 0xFF00, report ID 0x02) from:
  - OpenRazer PR #2862, driver/razerblackshark_driver.c
    https://github.com/openrazer/openrazer/pull/2862
  - HaloBattery providers/blackshark.py
    https://github.com/HeyOkay/HaloBattery/blob/main/providers/blackshark.py
Only frames used: remote mode on/off (0x02/0xE1), battery query (0x03/0x21),
charging query (0x03/0x2A). Nothing else is sent.

Usage: blackshark_battery.py [--listen SECONDS] [-v]
"""
import sys
import time

import hid

VID, PID = 0x1532, 0x0555
LEN = 64
VERBOSE = "-v" in sys.argv


def hx(b):
    return " ".join(f"{x:02x}" for x in b)


def frame_remote(on):
    b = bytearray(LEN)
    b[0], b[1], b[2], b[5], b[6], b[7], b[9], b[10], b[11] = (
        0x02, 0x80, 0x07, 0x50, 0x41, 0x0E, 0x02, 0xE1, 1 if on else 0)
    return bytes(b)


def frame_query(cmd):
    b = bytearray(LEN)
    b[0], b[1], b[2], b[5], b[6], b[7], b[9], b[10] = (
        0x02, 0x80, 0x08, 0x50, 0x41, 0x08, 0x03, cmd)
    return bytes(b)


def log(msg):
    if VERBOSE:
        print(msg, file=sys.stderr)


def write(dev, frame):
    n = dev.write(frame)
    log(f"TX ({n}): {hx(frame[:16])} ...")
    return n is not None and n > 0


def parse(data, cmd):
    d = list(data or [])
    for off in (0, -1):  # with / without leading report id
        c = 12 + off
        if len(d) > c + 3 and (off == -1 or d[0] == 0x02):
            if d[c] == cmd and d[c + 1] == 0x01:
                return d[c + 3:c + 3 + max(d[c + 2], 1)]
    return None


def query(dev, cmd, attempts=3, timeout=0.3):
    while dev.read(LEN, 5):  # drain
        pass
    write(dev, frame_remote(True))  # sacrificial wake-up frame
    time.sleep(0.035)
    result = None
    for _ in range(attempts):
        write(dev, frame_remote(True))
        time.sleep(0.035)
        write(dev, frame_query(cmd))
        end = time.time() + timeout
        while time.time() < end:
            data = dev.read(LEN, 50)
            if not data:
                continue
            log(f"RX: {hx(data[:24])} ...")
            p = parse(data, cmd)
            if p is not None:
                result = p
                break
        if result is not None:
            break
    write(dev, frame_remote(False))
    time.sleep(0.035)
    return result


def open_vendor():
    for d in hid.enumerate(VID, PID):
        if d["usage_page"] == 0xFF00:
            dev = hid.device()
            dev.open_path(d["path"])
            return dev
    sys.exit("BlackShark V2 Pro 2.4 dongle (vendor page 0xFF00) not found")


def main():
    dev = open_vendor()
    try:
        if "--listen" in sys.argv:
            secs = float(sys.argv[sys.argv.index("--listen") + 1])
            end = time.time() + secs
            n = 0
            while time.time() < end:
                data = dev.read(LEN, 200)
                if data:
                    n += 1
                    print(f"unsolicited RX: {hx(data)}")
            print(f"listen {secs:.0f}s: {n} input reports")
            return
        bat = query(dev, 0x21)
        if not bat:
            sys.exit("no battery reply (headset off or out of range?)")
        chg = query(dev, 0x2A)
        state = "unknown" if chg is None else ("charging" if chg[0] else "on battery")
        print(f"battery: {bat[0]}% ({state})")
    finally:
        dev.close()


if __name__ == "__main__":
    main()
