import Foundation

/// How the cats are drawn.
enum RenderStyle: String, CaseIterable {
    case flat
    case threeD = "3d"

    var title: String {
        switch self {
        case .flat: "Flat"
        case .threeD: "3D"
        }
    }
}

/// The choices DeskCats remembers between launches, kept in `UserDefaults`.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard
    private static let coatsKey = "coats"
    private static let sizeKey = "size"
    private static let styleKey = "style"

    /// The coats of the cats on the desk, oldest first, or nil on a first launch.
    static var coats: [Coat]? {
        get {
            guard let names = defaults.stringArray(forKey: coatsKey) else { return nil }
            return names.compactMap { name in Coat.all.first { $0.name == name } }
        }
        set { defaults.set(newValue?.map(\.name), forKey: coatsKey) }
    }

    /// The name of the chosen size, or nil if none was chosen yet.
    static var size: String? {
        get { defaults.string(forKey: sizeKey) }
        set { defaults.set(newValue, forKey: sizeKey) }
    }

    static var style: RenderStyle? {
        get { defaults.string(forKey: styleKey).flatMap(RenderStyle.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: styleKey) }
    }
}
