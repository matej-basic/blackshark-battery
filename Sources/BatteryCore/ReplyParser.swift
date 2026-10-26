import Foundation

/// Reads the dongle's input reports. A line-by-line port of `parse()` in
/// blackshark_battery.py, so both give the same answer for the same bytes.
///
/// Replies start with `02 0e 50 49`. Counting from the report ID at byte 0:
/// byte 12 echoes the command, byte 13 is `01` for ACK, byte 14 is the
/// payload length and the payload starts at byte 15.
public enum ReplyParser {
    /// The payload of a reply to `command`, or nil if `data` is not one.
    ///
    /// Tries the layout with the report ID first, then the one without it,
    /// like the script. As in the script, the second layout does not check
    /// byte 0. A payload length of 0 still returns one byte, and the slice is
    /// clamped to the end of the buffer the way Python slices are.
    public static func parse(_ data: [UInt8], command: Command) -> [UInt8]? {
        for off in [0, -1] {  // with / without leading report id
            let c = 12 + off
            if data.count > c + 3 && (off == -1 || data[0] == 0x02) {
                if data[c] == command.rawValue && data[c + 1] == 0x01 {
                    let n = max(Int(data[c + 2]), 1)
                    return Array(data[(c + 3)..<min(c + 3 + n, data.count)])
                }
            }
        }
        return nil
    }

    /// True for the status frames the dongle sends around every reply
    /// (`02 0d 50 49 01 c0 ...`). Only used to tag `-v` log lines; `parse`
    /// already rejects these frames on its own.
    public static func isStatusFrame(_ data: [UInt8]) -> Bool {
        data.starts(with: [0x02, 0x0D, 0x50, 0x49, 0x01, 0xC0])
    }
}

/// Bytes as lowercase hex pairs separated by spaces, like `hx()` in the script.
public func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
