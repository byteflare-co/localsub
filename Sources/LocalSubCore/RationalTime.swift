import Foundation

public struct RationalTime: Codable, Sendable, Hashable, Comparable {
    public let value: Int64
    public let timescale: Int32

    public init(value: Int64, timescale: Int32) throws {
        guard value >= 0, timescale > 0 else { throw LocalSubError.invalidTime }
        let divisor = Self.gcd(value, Int64(timescale))
        self.value = value / divisor
        self.timescale = Int32(Int64(timescale) / divisor)
    }

    private enum CodingKeys: String, CodingKey { case value, timescale }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(Int64.self, forKey: .value),
            timescale: container.decode(Int32.self, forKey: .timescale)
        )
    }

    public static let zero = try! RationalTime(value: 0, timescale: 1)

    public static func seconds(_ value: Int64) -> RationalTime {
        precondition(value >= 0)
        return try! RationalTime(value: value, timescale: 1)
    }

    public static func milliseconds(_ value: Int64) -> RationalTime {
        precondition(value >= 0)
        return try! RationalTime(value: value, timescale: 1_000)
    }

    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        let left = lhs.value.multipliedFullWidth(by: Int64(rhs.timescale))
        let right = rhs.value.multipliedFullWidth(by: Int64(lhs.timescale))
        if left.high != right.high { return left.high < right.high }
        return left.low < right.low
    }

    public func srtMilliseconds() throws -> Int64 {
        guard value >= 0, timescale > 0 else { throw LocalSubError.invalidTime }
        let (scaled, overflow) = value.multipliedReportingOverflow(by: 1_000)
        guard !overflow else { throw LocalSubError.invalidTime }
        let scale = Int64(timescale)
        let quotient = scaled / scale
        let remainder = scaled % scale
        return quotient + (remainder * 2 >= scale ? 1 : 0)
    }

    public var secondsDouble: Double {
        Double(value) / Double(timescale)
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }
}

public struct RationalTimeRange: Codable, Sendable, Hashable {
    public let start: RationalTime
    public let end: RationalTime

    public init(start: RationalTime, end: RationalTime) throws {
        guard start < end else { throw LocalSubError.invalidRange }
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey { case start, end }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            start: container.decode(RationalTime.self, forKey: .start),
            end: container.decode(RationalTime.self, forKey: .end)
        )
    }

    public var durationSeconds: Double {
        end.secondsDouble - start.secondsDouble
    }
}
