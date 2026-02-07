import Foundation

extension Data {
    /// Convert data to a hex-encoded string.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize data from a hex-encoded string.
    public init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
