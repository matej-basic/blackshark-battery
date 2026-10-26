import AppKit
import BatteryCore
import ServiceManagement

/// Owns the menu bar icon and its menu, and decides when to read the headset.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let dongleMonitor = DongleMonitor()
    private let reader: HeadsetReader
    private let policy = PollPolicy.withIntervalOverride(Settings.pollIntervalSeconds)

    private var state: HeadsetState = .starting
    /// Nil until the monitor has reported once, so the first report can be
    /// told apart from a later arrival.
    private var donglePresent: Bool?
    /// Goes up on every arrival and removal. A read whose generation is out
    /// of date when it finishes is dropped, so a slow "no reply" cannot
    /// overwrite "no dongle" after an unplug.
    private var dongleGeneration = 0
    private var inFlight = false
    private var lastAttempt: Date?
    /// Retryable read failures in a row; see `PollPolicy.consecutiveFailures`.
    private var failures = 0
    /// The one pending poll, either a short delay or the next regular read.
    private var pollTimer: Timer?

    // The menu is built once; these items are updated in place, so a read
    // that finishes while the menu is open shows up in it.
    private var headlineItem: NSMenuItem!
    private var detailItem: NSMenuItem!
    private var launchItemIndex = 0
    private var menuIsOpen = false

    init(frameLog: ((String) -> Void)?) {
        reader = HeadsetReader(log: frameLog)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The status item is the icon that lives in the menu bar.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.menu = buildMenu()

        dongleMonitor.onChange = { [weak self] devices in
            self?.dongleChanged(present: !devices.isEmpty)
        }
        dongleMonitor.start()

        refresh()
        observeSleepWake()
    }

    // MARK: Polling

    private func dongleChanged(present: Bool) {
        let firstReport = donglePresent == nil
        guard firstReport || present != donglePresent else { return }
        donglePresent = present
        dongleGeneration += 1
        failures = 0

        if present {
            if case .noDongle = state {
                state = .starting
            }
            refresh()
            apply(firstReport ? .launch : .dongleArrived)
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
            state = .noDongle
            refresh()
        }
    }

    /// Asks the policy whether to poll after `trigger`, and when.
    private func apply(_ trigger: PollTrigger) {
        let decision = policy.decide(
            trigger,
            dongle: dongleMonitor.service != nil,
            inFlight: inFlight,
            lastAttempt: lastAttempt,
            now: Date()
        )
        guard let delay = decision.pollAfter else { return }
        if delay <= 0 {
            poll()
        } else {
            schedulePoll(after: delay)
        }
    }

    /// Replaces the pending poll with a one-shot timer. It runs in the
    /// common modes so it also fires while the menu is open, and has some
    /// tolerance so macOS can coalesce wakeups.
    private func schedulePoll(after seconds: TimeInterval) {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            self?.apply(.timer)
        }
        timer.tolerance = min(30, seconds / 4)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard let service = dongleMonitor.service else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        inFlight = true
        lastAttempt = Date()
        let generation = dongleGeneration
        refresh()

        reader.read(service: service) { [weak self] outcome in
            // UI work must run on the main thread.
            DispatchQueue.main.async { self?.finish(outcome, generation: generation) }
        }
    }

    private func finish(_ outcome: ReadOutcome, generation: Int) {
        inFlight = false
        guard generation == dongleGeneration else {
            // The dongle came or went during the read. Its arrival could not
            // start a poll while this one ran, so start it now.
            refresh()
            if donglePresent == true {
                apply(.dongleArrived)
            }
            return
        }
        if case .openFailed(let failure) = outcome {
            logError("open failed: \(StatusText.hexCode(failure.code))")
        }
        state = state.applying(outcome).remembering(Settings.lastReading)
        if case .ok(let reading) = state {
            Settings.lastReading = reading
        }
        refresh()
        let present = donglePresent == true
        failures = policy.consecutiveFailures(after: outcome, donglePresent: present, previous: failures)
        schedulePoll(after: policy.nextTimer(after: outcome, state: state, donglePresent: present, failures: failures))
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        headlineItem = NSMenuItem(title: StatusText.reading, action: nil, keyEquivalent: "")
        headlineItem.isEnabled = false
        menu.addItem(headlineItem)
        detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        detailItem.isHidden = true
        menu.addItem(detailItem)

        menu.addItem(.separator())
        let refreshItem = item("Refresh now", action: #selector(refreshNow))
        refreshItem.keyEquivalent = "r"
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        launchItemIndex = menu.numberOfItems
        menu.addItem(launchAtLoginItem())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Updates the icon and the menu lines from the current state.
    func refresh() {
        guard let button = statusItem.button else { return }

        // SF Symbols are icons built into macOS. Template images let macOS
        // tint them for light/dark menu bars.
        let toolTip = StatusText.toolTip(state)
        let image = NSImage(systemSymbolName: StatusText.symbolName(state), accessibilityDescription: toolTip)
        image?.isTemplate = true
        button.image = image

        var title = StatusText.title(state)
        if image == nil && title.isEmpty {
            title = StatusText.fallbackTitle  // never let the item vanish
        }
        let attributed = NSMutableAttributedString(string: title)
        if StatusText.showsBolt(state), let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "charging") {
            bolt.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = bolt
            attributed.append(NSAttributedString(attachment: attachment))
        }
        button.attributedTitle = attributed
        button.appearsDisabled = StatusText.appearsDisabled(state)
        button.toolTip = toolTip

        headlineItem.title = StatusText.headline(state)
        let detail = StatusText.detail(state, inFlight: inFlight, now: Date())
        detailItem.title = detail ?? ""
        detailItem.isHidden = detail == nil

        // An open menu keeps its items; the next menuWillOpen catches up.
        if !menuIsOpen {
            replaceLaunchAtLoginItem()
        }
    }

    /// Swaps in a fresh "Launch at login" item, which reads the current status.
    private func replaceLaunchAtLoginItem() {
        guard let menu = statusItem.menu else { return }
        menu.removeItem(at: launchItemIndex)
        menu.insertItem(launchAtLoginItem(), at: launchItemIndex)
    }

    /// "Launch at login", using the system's login item service.
    private func launchAtLoginItem() -> NSMenuItem {
        let launchItem = item("Launch at login", action: #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled:
            launchItem.state = .on
        case .requiresApproval:
            // Registered, but the user still has to allow it in
            // System Settings > General > Login Items.
            launchItem.state = .on
            launchItem.title = "Launch at login (approve in System Settings)"
        default:
            launchItem.state = .off
        }
        return launchItem
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    func menuWillOpen(_ menu: NSMenu) {
        replaceLaunchAtLoginItem()
        menuIsOpen = true
        apply(.menuOpened)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    // MARK: Menu actions

    @objc private func refreshNow() {
        apply(.refreshNow)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            logError("launch at login: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    // MARK: Sleep and wake

    /// Stops the timer before sleep and reads again shortly after wake,
    /// once USB devices have re-enumerated.
    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply(.didWake)
        }
    }
}
