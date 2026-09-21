import AppKit

@MainActor
enum MainMenu {
    static func install(for appDelegate: AppDelegate) {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        applicationItem.submenu = applicationMenu(target: appDelegate)

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        fileItem.submenu = fileMenu(target: appDelegate)

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        editItem.submenu = editMenu()

        let goItem = NSMenuItem()
        mainMenu.addItem(goItem)
        goItem.submenu = goMenu()

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = windowMenu()
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private static func applicationMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Tim’s Markdown Reader")
        menu.addItem(withTitle: "About Tim’s Markdown Reader", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.items.last?.target = target
        let updates = menu.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = target
        let licenses = menu.addItem(withTitle: "Licenses…", action: #selector(AppDelegate.showLicenses(_:)), keyEquivalent: "")
        licenses.target = target
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        settings.target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Tim’s Markdown Reader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tim’s Markdown Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        let open = menu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        open.target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        menu.addItem(withTitle: "Back", action: #selector(MarkdownDocumentWindowController.goBack(_:)), keyEquivalent: "[")
        menu.addItem(withTitle: "Forward", action: #selector(MarkdownDocumentWindowController.goForward(_:)), keyEquivalent: "]")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Find…",
            action: #selector(MarkdownViewController.showFind(_:)),
            keyEquivalent: "f"
        )
        menu.addItem(
            withTitle: "Find Next",
            action: #selector(MarkdownViewController.findNext(_:)),
            keyEquivalent: "g"
        )
        let previous = menu.addItem(
            withTitle: "Find Previous",
            action: #selector(MarkdownViewController.findPrevious(_:)),
            keyEquivalent: "g"
        )
        previous.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }
}
