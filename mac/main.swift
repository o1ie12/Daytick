// Daytick — Mac app (window + menu bar panel) around the web app in ../index.html.
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var window: NSWindow!
    var hotKey: EventHotKeyRef?

    // Each view gets its own web view; they share one data store, and the page
    // listens for storage events, so the window and the panel stay in sync.
    func makeWebView(size: NSSize, ctx: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "todo")
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: "app")
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.load(URLRequest(url: URL(string: "app://todo/index.html?ctx=\(ctx)")!))
        return wv
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Menu bar panel
        let panelView = makeWebView(size: NSSize(width: 340, height: 460), ctx: "panel")
        let vc = NSViewController(); vc.view = panelView
        popover.contentViewController = vc
        popover.contentSize = panelView.frame.size
        popover.behavior = .transient

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "Daytick")
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Main window
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Daytick"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0x22/255, green: 0x22/255, blue: 0x22/255, alpha: 1)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 400)
        window.contentView = makeWebView(size: window.frame.size, ctx: "window")
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") { window.center() }
        showWindow()

        registerHotKey()
    }

    // The page asks to widen the menu bar panel when its side panel opens
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let w = body["panelWidth"] as? Double,
              message.webView === popover.contentViewController?.view else { return }
        popover.contentSize = NSSize(width: w, height: popover.contentSize.height)
    }

    // Links to the web (About, Updates) open in the default browser
    func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.scheme == "https" || url.scheme == "http",
           action.navigationType == .linkActivated || action.targetFrame == nil {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ wv: WKWebView, createWebViewWith c: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // Clicking the Dock icon reopens the window after it was closed
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWindow() }
        return true
    }

    @objc func showWindow() {
        popover.performClose(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { togglePanel() }
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        (popover.contentViewController?.view as? WKWebView)?.evaluateJavaScript("document.getElementById('new')?.focus()")
    }

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Daytick", action: #selector(showWindow), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shortcut: ⌥⌘T", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Quit Daytick", action: #selector(NSApp.terminate), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert(); a.messageText = "Couldn't change Open at Login"
            a.informativeText = "Move Daytick into Applications and try again.\n\n\(error.localizedDescription)"
            a.runModal()
        }
    }

    // Global ⌥⌘T toggles the menu bar panel (Carbon hot keys need no Accessibility permission).
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.togglePanel() }
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
app.setActivationPolicy(.regular)

// Standard Edit menu so ⌘C/⌘V/⌘A/⌘Z work in the text field
let mainMenu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem(), windowItem = NSMenuItem()
mainMenu.addItem(appItem); mainMenu.addItem(editItem); mainMenu.addItem(windowItem)
let appMenu = NSMenu(); appItem.submenu = appMenu
appMenu.addItem(withTitle: "Hide Daytick", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(withTitle: "Quit Daytick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
let edit = NSMenu(title: "Edit"); editItem.submenu = edit
edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
app.mainMenu = mainMenu
app.run()
