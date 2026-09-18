import CryptoKit
import Foundation

public enum TOTP {
    public static func normalizeSecret(_ secret: String) -> String {
        String(secret.filter { !$0.isWhitespace && $0 != "-" }).uppercased()
    }

    /// Returns nil when valid, otherwise a German error message.
    public static func validationError(_ secret: String) -> String? {
        let normalized = normalizeSecret(secret)
        if normalized.count < 8 {
            return "Das Secret ist zu kurz."
        }
        if base32Decode(normalized) == nil {
            return "Das Secret ist kein gültiges Base32."
        }
        return nil
    }

    public static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup = [Character: UInt8]()
        for (index, ch) in alphabet.enumerated() {
            lookup[ch] = UInt8(index)
        }

        var buffer: UInt64 = 0
        var bits = 0
        var output = Data()
        for ch in normalizeSecret(input) where ch != "=" {
            guard let value = lookup[ch] else {
                return nil
            }
            buffer = (buffer << 5) | UInt64(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> UInt64(bits)) & 0xFF))
            }
        }
        return output.isEmpty ? nil : output
    }

    public static func code(
        secret: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: String = "SHA1",
        date: Date = Date()
    ) -> String? {
        guard let key = base32Decode(secret) else {
            return nil
        }
        let step = period <= 0 ? 30 : period
        let size = (6...8).contains(digits) ? digits : 6
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(step)))
        return hotp(key: key, counter: counter, digits: size, algorithm: algorithm)
    }

    public static func hotp(key: Data, counter: UInt64, digits: Int, algorithm: String) -> String {
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
        let symmetricKey = SymmetricKey(data: key)

        let mac: Data
        switch algorithm.uppercased() {
        case "SHA256":
            mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case "SHA512":
            mac = Data(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        default:
            mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        }

        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits {
            modulus *= 10
        }
        let value = truncated % modulus
        let text = String(value)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }

    /// Seconds left in the current period, with fractions (for smooth progress).
    public static func remaining(period: Int = 30, date: Date = Date()) -> Double {
        let step = Double(period <= 0 ? 30 : period)
        return step - date.timeIntervalSince1970.truncatingRemainder(dividingBy: step)
    }

    public static func remainingSeconds(period: Int = 30, date: Date = Date()) -> Int {
        let step = period <= 0 ? 30 : period
        let seconds = Int(ceil(remaining(period: step, date: date)))
        return seconds <= 0 ? step : seconds
    }

    public static func progress(period: Int = 30, date: Date = Date()) -> Double {
        let step = Double(period <= 0 ? 30 : period)
        return remaining(period: period, date: date) / step
    }

    /// "482193" -> "482 193"; other lengths stay unchanged.
    public static func format(_ code: String) -> String {
        guard code.count == 6 else {
            return code
        }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}
