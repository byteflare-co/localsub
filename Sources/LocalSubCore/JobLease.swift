public struct JobLease: Sendable, Hashable {
    fileprivate let generation: UInt64
}

public struct JobLeaseGate: Sendable {
    private var generation: UInt64 = 0
    public init() {}

    public mutating func begin() -> JobLease {
        generation &+= 1
        return JobLease(generation: generation)
    }

    public mutating func invalidate() { generation &+= 1 }
    public func isCurrent(_ lease: JobLease) -> Bool { lease.generation == generation }
}

