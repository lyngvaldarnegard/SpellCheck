import Foundation
import SpellCheckCore

/// Text grabbed from the frontmost app, together with a closure that swaps
/// corrected text back into the exact place it came from.
public struct GrabbedText: Sendable {
    public let scope: TextScope
    public let replace: @Sendable (String) async -> Bool

    public init(scope: TextScope, replace: @escaping @Sendable (String) async -> Bool) {
        self.scope = scope
        self.replace = replace
    }
}

/// Anything that can capture the text the user wants corrected (selection or
/// current sentence) from the frontmost application.
public protocol TextSource: Sendable {
    func grab() async throws -> GrabbedText
}

public enum TextSourceError: Error, Sendable, Equatable {
    case noText
    case accessDenied
    case replaceFailed
}
