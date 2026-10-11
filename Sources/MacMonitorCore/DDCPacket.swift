/// DDC/CI (VESA MCCS) packet encoding over I2C. Pure byte math; the I2C transfer
/// itself is done by `DDCService` in the app target.
public enum DDCPacket {
    /// Virtual control registers (VCP codes).
    public static let vcpBrightness: UInt8 = 0x10
    public static let vcpContrast: UInt8 = 0x12
    public static let vcpPower: UInt8 = 0xD6
    public static let vcpInput: UInt8 = 0x60

    /// I2C address of the display (write) used as checksum seed.
    public static let displayAddress: UInt8 = 0x6E

    /// "Set VCP Feature" request: 0x51 0x84 0x03 <vcp> 0x00 <value> <checksum>.
    public static func setVCPFeature(_ vcpCode: UInt8, value: UInt8) -> [UInt8] {
        withChecksum([0x51, 0x84, 0x03, vcpCode, 0x00, value])
    }

    /// "Get VCP Feature" request: 0x51 0x82 0x01 <vcp> <checksum>.
    public static func getVCPFeature(_ vcpCode: UInt8) -> [UInt8] {
        withChecksum([0x51, 0x82, 0x01, vcpCode])
    }

    /// Parse a "Get VCP Feature" reply into current/max as 0...1. Nil if malformed.
    public static func parseVCPReply(_ reply: [UInt8], vcpCode: UInt8) -> Double? {
        guard reply.count >= 9, reply[2] == 0x02, reply[4] == vcpCode else { return nil }

        let currentValue = (UInt16(reply[7]) << 8) | UInt16(reply[8])
        let maxValue = (UInt16(reply[5]) << 8) | UInt16(reply[6])

        guard maxValue > 0 else { return nil }
        return Double(currentValue) / Double(maxValue)
    }

    /// Clamp 0...1 and convert to the 0...100 value written over DDC.
    public static func percentValue(_ value: Double) -> UInt8 {
        UInt8(max(0.0, min(1.0, value)) * 100)
    }

    private static func withChecksum(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [bytes.reduce(displayAddress, ^)]
    }
}
