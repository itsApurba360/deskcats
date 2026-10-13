import AppKit

/// An sRGB color stored as plain components so coats stay `Sendable`.
struct RGB: Sendable, Equatable {
    let r: CGFloat, g: CGFloat, b: CGFloat

    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }

    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    /// The same color mixed toward black by `amount` (0...1).
    func darker(_ amount: CGFloat) -> NSColor {
        NSColor(srgbRed: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: 1)
    }
}

/// The colors and markings that make one cat look different from another.
struct Coat: Sendable, Equatable {
    enum Pattern: Sendable, Equatable {
        case solid
        case stripes(RGB)
        case patches(RGB, RGB)
    }

    let name: String
    let base: RGB
    let pattern: Pattern
    /// Chest and belly patch, if the coat has one.
    let chest: RGB?
    /// Muzzle color, if it differs from the head.
    let muzzle: RGB?
    let paws: RGB
    let ears: RGB
    let tail: RGB
    let earInner: RGB
    let eyes: RGB
    let nose: RGB
    let outline: RGB

    static let all: [Coat] = [
        Coat(name: "Orange tabby", base: RGB(0xF2A65A), pattern: .stripes(RGB(0xD9772E)),
             chest: RGB(0xFCE6CC), muzzle: RGB(0xFCE6CC), paws: RGB(0xFCE6CC),
             ears: RGB(0xF2A65A), tail: RGB(0xF2A65A), earInner: RGB(0xF7B9B5),
             eyes: RGB(0x6BAA3C), nose: RGB(0xE88A8A), outline: RGB(0x6B3A16)),
        Coat(name: "Black", base: RGB(0x2B2B33), pattern: .solid,
             chest: nil, muzzle: nil, paws: RGB(0x2B2B33),
             ears: RGB(0x2B2B33), tail: RGB(0x2B2B33), earInner: RGB(0x5A4450),
             eyes: RGB(0xF0C93A), nose: RGB(0x4A3A42), outline: RGB(0x0E0E12)),
        Coat(name: "White", base: RGB(0xFAF8F5), pattern: .solid,
             chest: nil, muzzle: nil, paws: RGB(0xFAF8F5),
             ears: RGB(0xFAF8F5), tail: RGB(0xFAF8F5), earInner: RGB(0xF6B6C0),
             eyes: RGB(0x5BA4E0), nose: RGB(0xF29AAA), outline: RGB(0x8A8580)),
        Coat(name: "Grey", base: RGB(0x8E98A6), pattern: .solid,
             chest: RGB(0xB7BFCA), muzzle: RGB(0xB7BFCA), paws: RGB(0xB7BFCA),
             ears: RGB(0x8E98A6), tail: RGB(0x8E98A6), earInner: RGB(0xD9A8B4),
             eyes: RGB(0xE8B83A), nose: RGB(0x7E6A78), outline: RGB(0x3C4350)),
        Coat(name: "Calico", base: RGB(0xFBF7F0), pattern: .patches(RGB(0xEE9A4D), RGB(0x34312F)),
             chest: nil, muzzle: nil, paws: RGB(0xFBF7F0),
             ears: RGB(0xEE9A4D), tail: RGB(0x34312F), earInner: RGB(0xF6B6C0),
             eyes: RGB(0x7DA83A), nose: RGB(0xF29AAA), outline: RGB(0x5A4632)),
        Coat(name: "Tuxedo", base: RGB(0x26262E), pattern: .solid,
             chest: RGB(0xF7F5F2), muzzle: RGB(0xF7F5F2), paws: RGB(0xF7F5F2),
             ears: RGB(0x26262E), tail: RGB(0x26262E), earInner: RGB(0x5A4450),
             eyes: RGB(0x7CC46A), nose: RGB(0xE79AA6), outline: RGB(0x0E0E12)),
        Coat(name: "Brown tabby", base: RGB(0xA6825E), pattern: .stripes(RGB(0x5E4530)),
             chest: RGB(0xE6D3BC), muzzle: RGB(0xE6D3BC), paws: RGB(0xA6825E),
             ears: RGB(0xA6825E), tail: RGB(0xA6825E), earInner: RGB(0xE0A9A2),
             eyes: RGB(0x9DB83A), nose: RGB(0xC47A72), outline: RGB(0x3E2C1C)),
        Coat(name: "Siamese", base: RGB(0xF3E6D0), pattern: .solid,
             chest: nil, muzzle: RGB(0x5C4334), paws: RGB(0x5C4334),
             ears: RGB(0x5C4334), tail: RGB(0x5C4334), earInner: RGB(0x8A6A5A),
             eyes: RGB(0x4F9BE8), nose: RGB(0x3A2A22), outline: RGB(0x5A4636)),
    ]
}
