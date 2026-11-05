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

    public init(scope: TextScope, replace: @escaping @Sendable (String) async throws -> Void) {
        self.scope = scope
        self.replace = replace
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
    case replaceFailed
    /// The app the text was grabbed from can no longer be used (it quit, or
    /// focus could not be returned to it before replacing).
    case targetUnavailable(String)
}
