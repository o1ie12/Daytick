// To Do — menu bar wrapper around the web app in ../index.html.
// Serves the bundled web files from a custom app:// scheme so localStorage persists.
import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    let root = Bundle.main.resourceURL!.appendingPathComponent("web")
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        var path = task.request.url?.path ?? "/"
        if path == "/" || path.isEmpty { path = "/index.html" }
        let file = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let types = ["html": "text/html", "js": "text/javascript", "svg": "image/svg+xml",
                     "png": "image/png", "webmanifest": "application/manifest+json"]
        let mime = types[file.pathExtension] ?? "application/octet-stream"
        task.didReceive(URLResponse(url: task.request.url!, mimeType: mime,
                                    expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var webView: WKWebView!
    var window: NSWindow?
    var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: "app")
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 640), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: URL(string: "app://todo/index.html")!))

        let vc = NSViewController(); vc.view = webView
        popover.contentViewController = vc
        popover.contentSize = webView.frame.size
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "To Do")
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        registerHotKey()
    }

    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    @objc func toggle() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        webView.evaluateJavaScript("document.getElementById('new')?.focus()")
    }

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: window == nil ? "Open in Window" : "Back to Menu Bar",
                     action: #selector(toggleWindow), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shortcut: ⌥⌘T", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // Moves the single web view between the popover and a regular window.
    @objc func toggleWindow() {
        if let w = window { w.close(); return }
        popover.performClose(nil)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "To Do"
        w.titlebarAppearsTransparent = true
        w.backgroundColor = NSColor(red: 0x22/255, green: 0x22/255, blue: 0x22/255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.delegate = self
        popover.contentViewController?.view = NSView()
        w.contentView = webView
        w.center()
        window = w
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ n: Notification) {
        window?.contentView = NSView()
        popover.contentViewController?.view = webView
        webView.frame.size = popover.contentSize
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert(); a.messageText = "Couldn't change Open at Login"
            a.informativeText = "Move To Do into Applications and try again.\n\n\(error.localizedDescription)"
            a.runModal()
        }
    }

    // Global ⌥⌘T via Carbon hot keys (no Accessibility permission needed).
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey),
                            EventHotKeyID(signature: OSType(0x54444f21), id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Standard Edit menu so ⌘C/⌘V/⌘A/⌘Z work in the text field
let mainMenu = NSMenu(), editItem = NSMenuItem()
mainMenu.addItem(editItem)
let edit = NSMenu(title: "Edit"); editItem.submenu = edit
edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
app.mainMenu = mainMenu
app.run()
