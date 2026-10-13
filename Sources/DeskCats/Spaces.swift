import Foundation

/// The user's Spaces (desktops and full-screen apps), read from the window server.
///
/// macOS has no public API for this, so it looks up the private CoreGraphics
/// calls at run time. If they are missing, `active` and `ordered` return nil and
/// the cats guess instead.
@MainActor
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let anyImage = UnsafeMutableRawPointer(bitPattern: -2)
    private static let connection: Int32? = lookUp("CGSMainConnectionID", as: MainConnection.self).map { $0() }
    private static let getActive = lookUp("CGSGetActiveSpace", as: GetActiveSpace.self)
    private static let copyDisplaySpaces = lookUp("CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)

    /// The Space on screen now.
    static var active: UInt64? {
        guard let connection, let getActive else { return nil }
        let id = getActive(connection)
        return id == 0 ? nil : id
    }

    /// Every Space, left to right as the trackpad swipes through them.
    static var ordered: [UInt64]? {
        guard let connection, let copyDisplaySpaces,
              let displays = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        return displays.flatMap { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap {
                ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value
            }
        }
    }

    private static func lookUp<T>(_ name: String, as type: T.Type) -> T? {
        dlsym(anyImage, name).map { unsafeBitCast($0, to: type) }
    }
}
