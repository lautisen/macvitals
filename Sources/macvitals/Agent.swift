import AppKit
import MacVitalsCore

/// Menu bar agent running as the logged-in user. It is the transparency half of the tool:
/// the user always knows monitoring is on, until when, and can read the exact report IT gets.
final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let paths = Paths.system
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var status: PublicStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refresh()
        guard let status, status.active else { NSApp.terminate(nil); return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MacVitals monitoring")
        item.button?.toolTip = "MacVitals: performance monitoring is active"
        statusItem = item
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
            if self?.status?.active != true { NSApp.terminate(nil) }
            self?.rebuildMenu()
        }

        let key = "noticeShown-\(Int(status.startDate.timeIntervalSince1970))"
        if status.showNotice && !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            showNotice()
        }
    }

    private func refresh() {
        status = JSONFile.read(PublicStatus.self, from: paths.publicStatusFile)
    }

    private func rebuildMenu() {
        guard let status else { return }
        let dates = DateFormatter()
        dates.dateStyle = .medium
        dates.timeStyle = .short

        let menu = NSMenu()
        menu.addItem(disabled("Performance monitoring is active"))
        menu.addItem(disabled("By: \(status.organizationName)"))
        menu.addItem(disabled(status.endDate.map { "Ends: \(dates.string(from: $0))" } ?? "No end date"))
        if let last = status.lastReportDate { menu.addItem(disabled("Last report: \(dates.string(from: last))")) }
        menu.addItem(.separator())
        menu.addItem(action("Open the report IT receives", #selector(openReport)))
        menu.addItem(action("What is collected?", #selector(showNotice)))
        menu.addItem(.separator())
        menu.addItem(action("Hide this icon", #selector(hideIcon)))
        statusItem?.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openReport() {
        if FileManager.default.isReadableFile(atPath: paths.latestReportFile.path) {
            NSWorkspace.shared.open(paths.latestReportFile)
        } else {
            alert("No report yet", "The first report is generated a few minutes after installation.")
        }
    }

    @objc private func showNotice() {
        guard let status else { return }
        let dates = DateFormatter()
        dates.dateStyle = .long
        dates.timeStyle = .short
        let until = status.endDate.map { "until \(dates.string(from: $0))" } ?? "until IT removes it"
        let processes = status.collectsProcessNames ? "\n• Names of the busiest apps and processes, with their CPU and memory use" : ""
        alert("Performance monitoring is active",
              """
              \(status.organizationName) is measuring this Mac's performance \(until) to diagnose slowness or hardware problems.

              Collected every few minutes:
              • CPU, memory, disk space, battery and temperature\(processes)
              • Kernel panics (system crashes)

              Never collected: your files, keystrokes, screen, messages or browsing history.

              You can open the exact report IT receives from the menu bar icon. Questions: \(status.supportContact).
              """)
    }

    /// Hides the icon only. Monitoring itself is controlled by IT and keeps running.
    @objc private func hideIcon() {
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum Agent {
    static func run() -> Never {
        let app = NSApplication.shared
        let delegate = AgentDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }
}
