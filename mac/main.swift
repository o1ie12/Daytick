// Daytick — Mac app (window + menu bar panel) around the web app in ../index.html.
// Serves the bundled web files from a custom app:// scheme so localStorage persists.
import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

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
                     "png": "image/png", "webmanifest": "application/manifest+json", "woff2": "font/woff2"]
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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "Daytick")
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.target = self
        statusItem.button?.imagePosition = .imageLeading
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
        applyDockPolicy()
        if showInDock { showWindow() }

        registerHotKey()
    }

    // Messages from the page: panel width, Dock visibility, open the window
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let w = body["panelWidth"] as? Double, message.webView === popover.contentViewController?.view {
            popover.contentSize = NSSize(width: w, height: popover.contentSize.height)
        }
        if let dock = body["dock"] as? Bool, dock != showInDock {
            showInDock = dock
            applyDockPolicy()
        }
        if body["open"] as? String == "window" { showWindow() }
        // Tasks left, shown next to the menu bar icon (0 hides it)
        if let n = body["count"] as? Int {
            statusItem.button?.title = n > 0 ? " \(n)" : ""
        }
        if let json = body["export"] as? String { saveBackup(json, name: body["filename"] as? String, from: message.webView) }
        if body["import"] as? Bool == true { openBackup(into: message.webView) }
    }

    // Backups use native Save/Open dialogs; the page builds and restores the JSON.
    func saveBackup(_ json: String, name: String?, from wv: WKWebView?) {
        popover.performClose(nil)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name ?? "daytick-backup.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            wv?.evaluateJavaScript("backupSaved()")
        } catch { alert("Couldn't save the backup", error.localizedDescription) }
    }

    func openBackup(into wv: WKWebView?) {
        popover.performClose(nil)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let confirm = NSAlert()
        confirm.messageText = "Restore this backup?"
        confirm.informativeText = "Your current tasks, history and settings will be replaced."
        confirm.addButton(withTitle: "Restore")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        // Restore in the window's page; the storage event syncs the menu bar panel
        let target = window.contentView as? WKWebView ?? wv
        target?.callAsyncJavaScript("return restoreBackup(text)", arguments: ["text": text], in: nil, in: .page) { result in
            if case .success(let ok) = result, ok as? Bool == false {
                self.alert("That file isn't a Daytick backup", "Choose a file saved with “save backup”.")
            }
        }
    }

    func alert(_ title: String, _ info: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = info; a.runModal()
    }

    // Remembered natively too, so a menu-bar-only launch doesn't flash the window or Dock icon
    var showInDock: Bool {
        get { UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showInDock") }
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        // Switching to .accessory hides the app's windows; bring the window back if it was open
        if window.isVisible { DispatchQueue.main.async { self.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) } }
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
