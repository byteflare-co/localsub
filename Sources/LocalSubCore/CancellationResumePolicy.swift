public enum CancellationResumeDestination: Sendable, Equatable {
    case empty
    case ready
    case review
}

public enum CancellationResumePolicy {
    public static func destination(
        hasSource: Bool,
        hasReviewableCues: Bool
    ) -> CancellationResumeDestination {
        guard hasSource else { return .empty }
        return hasReviewableCues ? .review : .ready
    }
}
