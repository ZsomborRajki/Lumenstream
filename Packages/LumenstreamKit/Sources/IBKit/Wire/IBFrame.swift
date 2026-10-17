import Foundation

/// Length-prefixed framing used by the TWS API (client/server version 100+):
/// every message is a 4-byte big-endian length followed by that many payload bytes.
public enum IBFrame {
    /// Defensive upper bound. Real messages are far smaller; anything bigger
    /// means we lost framing sync and should drop the connection.
    public static let maximumLength = 16 * 1024 * 1024

    /// Size of the big-endian length prefix.
    public static let headerLength = 4

    /// Raw bytes sent before the very first frame to announce a v100+ client.
    public static let apiPrefix = Data("API\0".utf8)

    public static func encode(_ payload: Data) -> Data {
        var frame = Data(capacity: headerLength + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    /// Reads the payload length from a 4-byte header. Works on `Data` slices
    /// with a non-zero start index, which is what socket reads hand back.
    public static func payloadLength(header: Data) -> Int {
        Int(header.prefix(headerLength).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}
