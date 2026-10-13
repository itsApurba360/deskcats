import AppKit

/// Development aid: `DeskCats --render-sheet out.png` paints every coat in every
/// pose into one image, so the drawing can be checked without the overlay.
@MainActor
enum PoseSheet {
    private static let poses: [(Cat.Activity, CGFloat, CGFloat)] = [
        (.walk, 0, 0.9), (.idle, 0, 0), (.sit, 0, 0), (.groom, 0, 0), (.stretch, 0.5, 0),
        (.sleep, 0, 0), (.loaf, 0, 0), (.chaseTail, 0, 0), (.bat, 0, 0), (.slowBlink, 0.8, 0),
        (.yawn, 0.5, 0), (.hop, 0.5, 0), (.pounce, 0.3, 0), (.pounce, 0.7, 0), (.scratch, 0, 0),
        (.purr, 0, 0), (.held, 0, 0),
    ]

    static func write(to path: String) -> Bool {
        let cell = CGSize(width: 150, height: 150)
        let pixelScale: CGFloat = 2
        let size = CGSize(width: cell.width * CGFloat(poses.count), height: cell.height * CGFloat(Coat.all.count))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * pixelScale), pixelsHigh: Int(size.height * pixelScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return false }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (row, coat) in Coat.all.enumerated() {
            for (column, entry) in poses.enumerated() {
                let origin = CGPoint(x: CGFloat(column) * cell.width,
                                     y: size.height - CGFloat(row + 1) * cell.height)
                let shade: CGFloat = (row + column).isMultiple(of: 2) ? 0.55 : 0.75
                NSColor(srgbRed: shade * 0.8, green: shade * 0.88, blue: shade, alpha: 1).setFill()
                CGRect(origin: origin, size: cell).fill()
                let pose = CatPainter.Pose(coat: coat, activity: entry.0, progress: entry.1,
                                           legPhase: entry.2, age: 1.3, blinking: false,
                                           look: CGVector(dx: 0.4, dy: 0.2))
                CatView.render(pose, scale: CatView.baseScale, facingRight: true,
                               at: CGPoint(x: origin.x + cell.width / 2, y: origin.y + 14))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
