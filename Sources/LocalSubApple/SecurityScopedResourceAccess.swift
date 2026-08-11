import Foundation

/// Holds a user-selected security-scoped URL open for the lifetime of this object.
/// A `false` result from `startAccessingSecurityScopedResource()` means either that
/// access was not needed or could not be started; the actual file operation remains
/// the source of truth and will report a permission error in the latter case.
public final class SecurityScopedResourceAccess {
    private let didStart: Bool
    private let stop: () -> Void

    public convenience init(url: URL) {
        self.init(
            start: { url.startAccessingSecurityScopedResource() },
            stop: { url.stopAccessingSecurityScopedResource() }
        )
    }

    init(start: () -> Bool, stop: @escaping () -> Void) {
        didStart = start()
        self.stop = stop
    }

    deinit {
        if didStart { stop() }
    }
}
