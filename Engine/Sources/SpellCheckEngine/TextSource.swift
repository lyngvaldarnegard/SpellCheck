import Foundation
import SpellCheckCore

/// Text grabbed from the frontmost app, together with a closure that swaps
/// edited text back into the exact place it came from.
public struct GrabbedText: Sendable {
    public let scope: TextScope
    /// Writes edited text back to the exact place it came from. Throws when
    /// the original target can no longer be safely used or the write could
    /// not be performed/verified.
    public let replace: @Sendable (String) async throws -> Void
    /// Returns keyboard focus to the app the text was grabbed from without
    /// replacing anything (used when the picker is cancelled).
    public let refocus: (@Sendable () async -> Void)?

    public init(scope: TextScope, replace: @escaping @Sendable (String) async throws -> Void, refocus: (@Sendable () async -> Void)? = nil) {
        self.scope = scope
        self.replace = replace
        self.refocus = refocus
    }
}

/// Anything that can capture the text the user wants edited (selection or
/// current sentence) from the frontmost application.
public protocol TextSource: Sendable {
    func grab() async throws -> GrabbedText
}

public enum TextSourceError: Error, Sendable, Equatable {
    case noText
    case accessDenied
    /// The replacement could not be issued at all — nothing was written to
    /// the target document.
    case replaceFailed
    /// The app the text was grabbed from can no longer be used (it quit, or
    /// focus could not be returned to it before replacing).
    case targetUnavailable(String)
    /// The original selection is no longer intact in the target app (the user
    /// clicked elsewhere or the selection changed). Nothing was written.
    case selectionChanged(String)
    /// The replacement was issued (e.g. pasted) but the result could not be
    /// verified — the document may already have changed. Never retried.
    case unverified(String)
}
