import AppKit
import ServiceManagement

@main
final class WallpaperApp: NSObject, NSApplicationDelegate {
    private let renderer = NetRenderer()
    private var displays: [NetDisplay] = []
    private var statusItem: NSStatusItem?
    private var clickMonitor: Any?
    private var paused = false
    private var asleep = false

    static func main() {
        let app = NSApplication.shared
        let delegate = WallpaperApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildDisplays()
        buildMenu()

        // A left press is held: the cloth stays bunched under the pointer and follows a drag until it lifts.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp]) { e in
            switch e.type {
            case .leftMouseDown: NetTaps.emit(NSEvent.mouseLocation, hold: true)
            case .leftMouseDragged: NetTaps.drag(NSEvent.mouseLocation)
            case .leftMouseUp: NetTaps.release()
            default: NetTaps.emit(NSEvent.mouseLocation)
            }
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        refresh()
    }

    private func buildDisplays() {
        displays.forEach { $0.close() }
        displays = NSScreen.screens.map { NetDisplay(screen: $0, renderer: renderer) }
    }

    @objc private func refresh() {
        let still = paused || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        displays.forEach { $0.update(still: still, asleep: asleep) }
    }

    @objc private func screensChanged() {
        buildDisplays()
        refresh()
    }

    @objc private func screensSlept() {
        asleep = true
        refresh()
    }

    @objc private func screensWoke() {
        asleep = false
        renderer.restartClock()
        refresh()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Markade Wallpaper")

        let menu = NSMenu()
        let pause = menu.addItem(withTitle: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        let login = menu.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Markade Wallpaper", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.target = NSApp
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePause(_ item: NSMenuItem) {
        paused.toggle()
        item.title = paused ? "Resume" : "Pause"
        refresh()
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        item.state = service.status == .enabled ? .on : .off
    }
}
