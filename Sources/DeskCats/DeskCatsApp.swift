import AppKit

@main
enum DeskCatsApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-sheet"), index + 1 < arguments.count {
            exit(PoseSheet.write(to: arguments[index + 1]) ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
