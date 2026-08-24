import Cocoa
import Foundation

let kPreservePy = "/Volumes/qbitOS/00.dev/grokbotsGH/fc-preserve/preserve.py"
let kDefaultVault = "/Volumes/MacBookPro - Data/FC-Preserve"
let kIdevice = "/opt/homebrew/bin/idevice_id"
let kBabyUDID = "4ea7e05b3045f0e9036275125a85225dd6dd9bb9"
let kWaiterNeedle = "fc-preserve-wait.sh"

enum WizardStep: Int {
    case device = 1
    case target = 2
    case backup = 3
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let ui = PreserveWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logApp("didFinishLaunching screens=\(NSScreen.screens.count)")
        if ui.window == nil {
            ui.build()
        }
        ui.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.ui.show()
            logApp("async show visible=\(self.ui.window.isVisible) frame=\(self.ui.window.frame)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

final class PreserveWindow: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var window: NSWindow!
    var step: WizardStep = .device
    var alias = "GrokBotBaby"
    var running = false
    var proc: Process?
    var timer: Timer?

    var stepDots: [NSView] = []
    var stepLabels: [NSTextField] = []
    var card: NSView!
    var devicePane: NSView!
    var targetPane: NSView!
    var backupPane: NSView!
    var babyRadio: NSButton!
    var brickRadio: NSButton!
    var usbBadge: NSTextField!
    var usbDetail: NSTextField!
    var destField: NSTextField!
    var destError: NSTextField!
    var logView: NSTextView!
    var backBtn: NSButton!
    var primaryBtn: NSButton!
    var flashBtn: NSButton!
    var footNote: NSTextField!
    var deviceHint: NSTextField!

    func build() {
        let rect = NSRect(x: 0, y: 0, width: 760, height: 620)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FC-Preserve"
        window.minSize = NSSize(width: 700, height: 540)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.102, green: 0.110, blue: 0.125, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()

        let root = NSView(frame: rect)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.102, green: 0.110, blue: 0.125, alpha: 1).cgColor
        window.contentView = root

        let header = NSTextField(labelWithString: "FC-Preserve")
        header.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        header.textColor = NSColor.white
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let sub = NSTextField(labelWithString: "backup  ·  extract  ·  catalog  ·  SHA-256  ·  gate")
        sub.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        sub.textColor = NSColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1)
        sub.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sub)

        let stepper = makeStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stepper)

        card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0.145, green: 0.157, blue: 0.176, alpha: 1).cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        devicePane = makeDevicePane()
        targetPane = makeTargetPane()
        backupPane = makeBackupPane()
        for pane in [devicePane, targetPane, backupPane] as [NSView] {
            pane.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
                pane.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
                pane.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
                pane.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            ])
        }

        backBtn = button("Back", filled: false, action: #selector(goBack))
        primaryBtn = button("Continue", filled: true, action: #selector(goNext))
        flashBtn = button("flash locked (gate not ready)", filled: false, action: nil)
        flashBtn.isEnabled = false
        flashBtn.bezelColor = NSColor(srgbRed: 0.25, green: 0.26, blue: 0.29, alpha: 1)
        flashBtn.contentTintColor = NSColor.secondaryLabelColor
        flashBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        primaryBtn.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backBtn)
        root.addSubview(primaryBtn)
        root.addSubview(flashBtn)

        footNote = NSTextField(labelWithString: "Never flashes. linux / Etcher stay off until gate.ready.")
        footNote.font = NSFont.systemFont(ofSize: 11)
        footNote.textColor = NSColor(srgbRed: 0.50, green: 0.52, blue: 0.56, alpha: 1)
        footNote.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footNote)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            sub.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            sub.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            stepper.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
            stepper.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stepper.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stepper.heightAnchor.constraint(equalToConstant: 44),
            card.topAnchor.constraint(equalTo: stepper.bottomAnchor, constant: 14),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            card.bottomAnchor.constraint(equalTo: primaryBtn.topAnchor, constant: -16),
            primaryBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            primaryBtn.bottomAnchor.constraint(equalTo: footNote.topAnchor, constant: -8),
            primaryBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 168),
            primaryBtn.heightAnchor.constraint(equalToConstant: 36),
            backBtn.trailingAnchor.constraint(equalTo: primaryBtn.leadingAnchor, constant: -10),
            backBtn.centerYAnchor.constraint(equalTo: primaryBtn.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 88),
            backBtn.heightAnchor.constraint(equalToConstant: 36),
            flashBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            flashBtn.centerYAnchor.constraint(equalTo: primaryBtn.centerYAnchor),
            flashBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            flashBtn.heightAnchor.constraint(equalToConstant: 36),
            footNote.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            footNote.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        applyStep()
        refreshUSB()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshUSB()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func show() {
        // Prefer the menu-bar / primary screen so the window is not stranded on a side display.
        let screen = NSScreen.screens.first ?? NSScreen.main
        if let screen = screen {
            let vis = screen.visibleFrame
            let size = NSSize(width: 760, height: 620)
            let origin = NSPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        logApp("show frame=\(window.frame) screen=\(String(describing: window.screen?.localizedName)) appWindows=\(NSApp.windows.count) screens=\(NSScreen.screens.count)")
    }

    private func makeStepper() -> NSView {
        let row = NSView()
        let titles = ["SELECT DEVICE", "SELECT TARGET", "BACKUP + verify"]
        var last: NSView?
        for (i, title) in titles.enumerated() {
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(wrap)

            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 11
            dot.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(dot)
            stepDots.append(dot)

            let num = NSTextField(labelWithString: "\(i + 1)")
            num.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            num.alignment = .center
            num.translatesAutoresizingMaskIntoConstraints = false
            num.tag = 900 + i
            wrap.addSubview(num)

            let lab = NSTextField(labelWithString: title)
            lab.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            lab.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(lab)
            stepLabels.append(lab)

            NSLayoutConstraint.activate([
                wrap.topAnchor.constraint(equalTo: row.topAnchor),
                wrap.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                wrap.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
                dot.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
                dot.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 22),
                dot.heightAnchor.constraint(equalToConstant: 22),
                num.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
                num.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
                lab.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
                lab.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                lab.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            ])
            if let last = last {
                wrap.leadingAnchor.constraint(equalTo: last.trailingAnchor, constant: 18).isActive = true
            } else {
                wrap.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
            }
            last = wrap
        }
        return row
    }

    private func makeDevicePane() -> NSView {
        let v = NSView()
        let title = NSTextField(labelWithString: "SELECT DEVICE")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title)

        babyRadio = NSButton(radioButtonWithTitle: "GrokBotBaby     iPhone 7 Plus · A10 checkm8 · default", target: self, action: #selector(pickDevice(_:)))
        babyRadio.state = .on
        babyRadio.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        babyRadio.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(babyRadio)

        brickRadio = NSButton(radioButtonWithTitle: "Brick     daily iPhone · Continuity · never flash", target: self, action: #selector(pickDevice(_:)))
        brickRadio.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        brickRadio.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(brickRadio)

        deviceHint = NSTextField(wrappingLabelWithString: "GrokBotBaby — preserve everything locally. Flash stays locked until linux-gate.json ready.")
        deviceHint.font = NSFont.systemFont(ofSize: 12)
        deviceHint.textColor = NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1)
        deviceHint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(deviceHint)

        usbBadge = NSTextField(wrappingLabelWithString: "USB: probing…")
        usbBadge.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        usbBadge.textColor = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.25, alpha: 1)
        usbBadge.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(usbBadge)

        usbDetail = NSTextField(wrappingLabelWithString: "")
        usbDetail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        usbDetail.textColor = NSColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1)
        usbDetail.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(usbDetail)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            babyRadio.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            babyRadio.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            babyRadio.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),
            brickRadio.topAnchor.constraint(equalTo: babyRadio.bottomAnchor, constant: 10),
            brickRadio.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            deviceHint.topAnchor.constraint(equalTo: brickRadio.bottomAnchor, constant: 14),
            deviceHint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            deviceHint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            usbBadge.topAnchor.constraint(equalTo: deviceHint.bottomAnchor, constant: 22),
            usbBadge.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            usbBadge.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            usbDetail.topAnchor.constraint(equalTo: usbBadge.bottomAnchor, constant: 8),
            usbDetail.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            usbDetail.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        return v
    }

    private func makeTargetPane() -> NSView {
        let v = NSView()
        let title = NSTextField(labelWithString: "SELECT TARGET")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title)

        let hint = NSTextField(wrappingLabelWithString: "Vault root for backup → extract → catalog → SHA-256 → linux-gate.json. Not Internal. Not the lab SSD.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1)
        hint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(hint)

        destField = NSTextField(string: kDefaultVault)
        destField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        destField.delegate = self
        destField.translatesAutoresizingMaskIntoConstraints = false
        destField.placeholderString = kDefaultVault
        destField.isEditable = true
        destField.isBezeled = true
        destField.bezelStyle = .roundedBezel
        destField.target = self
        destField.action = #selector(destChanged)
        v.addSubview(destField)

        let browse = button("Browse…", filled: false, action: #selector(browseDest))
        browse.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(browse)

        destError = NSTextField(wrappingLabelWithString: "")
        destError.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        destError.textColor = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.38, alpha: 1)
        destError.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(destError)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            destField.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 18),
            destField.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            destField.trailingAnchor.constraint(equalTo: browse.leadingAnchor, constant: -10),
            destField.heightAnchor.constraint(equalToConstant: 28),
            browse.centerYAnchor.constraint(equalTo: destField.centerYAnchor),
            browse.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            browse.widthAnchor.constraint(equalToConstant: 96),
            destError.topAnchor.constraint(equalTo: destField.bottomAnchor, constant: 12),
            destError.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            destError.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        return v
    }

    private func makeBackupPane() -> NSView {
        let v = NSView()
        let title = NSTextField(labelWithString: "BACKUP + verify")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(title)

        let hint = NSTextField(wrappingLabelWithString: "Runs preserve.py all <alias> only. Streams stdout here. Does not call linux. Does not flash.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1)
        hint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(hint)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 6
        v.addSubview(scroll)

        logView = NSTextView()
        logView.isEditable = false
        logView.isRichText = true
        logView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.backgroundColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        logView.textColor = NSColor(srgbRed: 0.82, green: 0.86, blue: 0.80, alpha: 1)
        logView.autoresizingMask = [.width, .height]
        logView.string = "Ready. Press Backup + verify when the phone is on USB (mux).\n"
        scroll.documentView = logView

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }

    private func button(_ title: String, filled: Bool, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: action == nil ? nil : self, action: action)
        b.bezelStyle = .rounded
        if filled {
            if #available(macOS 11.0, *) {
                b.controlSize = .large
            }
            b.keyEquivalent = "\r"
        }
        return b
    }

    private func applyStep() {
        devicePane.isHidden = step != .device
        targetPane.isHidden = step != .target
        backupPane.isHidden = step != .backup
        backBtn.isHidden = step == .device
        backBtn.isEnabled = !running

        let accent = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.16, alpha: 1)
        let dim = NSColor(srgbRed: 0.28, green: 0.30, blue: 0.34, alpha: 1)
        for (i, dot) in stepDots.enumerated() {
            let on = (i + 1) == step.rawValue
            dot.layer?.backgroundColor = (on ? accent : dim).cgColor
            stepLabels[i].textColor = on ? .white : NSColor(srgbRed: 0.55, green: 0.57, blue: 0.60, alpha: 1)
            if let num = dot.superview?.viewWithTag(900 + i) as? NSTextField {
                num.textColor = on ? NSColor.black : NSColor(srgbRed: 0.75, green: 0.76, blue: 0.78, alpha: 1)
            }
        }

        flashBtn.isHidden = step != .backup
        flashBtn.isEnabled = false
        flashBtn.title = "flash locked (gate not ready)"

        switch step {
        case .device:
            primaryBtn.title = "Continue"
            primaryBtn.isEnabled = true
            primaryBtn.keyEquivalent = "\r"
        case .target:
            primaryBtn.title = "Continue"
            _ = validateDest(show: true)
            primaryBtn.keyEquivalent = "\r"
        case .backup:
            primaryBtn.title = running ? "Running…" : "Backup + verify"
            primaryBtn.isEnabled = !running && validateDest(show: false)
            primaryBtn.keyEquivalent = running ? "" : "\r"
        }
    }

    @objc func pickDevice(_ sender: NSButton) {
        if sender == brickRadio {
            alias = "Brick"
            babyRadio.state = .off
            brickRadio.state = .on
            deviceHint.stringValue = "Brick is the daily phone — preserve only, never flash."
        } else {
            alias = "GrokBotBaby"
            babyRadio.state = .on
            brickRadio.state = .off
            deviceHint.stringValue = "GrokBotBaby — preserve everything locally. Flash stays locked until linux-gate.json ready."
        }
    }

    @objc func goBack() {
        if running { return }
        if step == .backup { step = .target }
        else if step == .target { step = .device }
        applyStep()
    }

    @objc func goNext() {
        if step == .device {
            step = .target
            applyStep()
            return
        }
        if step == .target {
            if validateDest(show: true) {
                step = .backup
                applyStep()
                appendLog("Target: \(destField.stringValue)\nDevice: \(alias)\n")
            }
            return
        }
        if step == .backup {
            startBackup()
        }
    }

    @objc func destChanged() {
        _ = validateDest(show: true)
        if step == .target {
            primaryBtn.isEnabled = validateDest(show: false)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        destChanged()
    }

    @objc func browseDest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: destField.stringValue)
        panel.prompt = "Select vault"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            self.destField.stringValue = url.path
            self.destChanged()
        }
    }

    @discardableResult
    func validateDest(show: Bool) -> Bool {
        let raw = destField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (raw as NSString).expandingTildeInPath
        let home = NSHomeDirectory()
        let docs = (home as NSString).appendingPathComponent("Documents")
        var reason: String?
        if raw.isEmpty {
            reason = "Need a vault path."
        } else if expanded == "/Volumes/qbitOS" || expanded.hasPrefix("/Volumes/qbitOS/") {
            reason = "Refuse /Volumes/qbitOS — qbitOS is lab SSD not the vault."
        } else if expanded == docs || expanded.hasPrefix(docs + "/") || expanded.contains("/Documents/FC-Preserve") && expanded.hasPrefix(home) {
            reason = "Refuse ~/Documents — Internal too tight. Use /Volumes/MacBookPro - Data/FC-Preserve."
        } else if expanded.hasPrefix("/Users/") && expanded.contains("/Documents") {
            reason = "Refuse ~/Documents — Internal too tight. Use /Volumes/MacBookPro - Data/FC-Preserve."
        }
        if show {
            destError.stringValue = reason ?? "OK — vault on the Data volume."
            destError.textColor = reason == nil
                ? NSColor(srgbRed: 0.45, green: 0.78, blue: 0.52, alpha: 1)
                : NSColor(srgbRed: 0.95, green: 0.45, blue: 0.38, alpha: 1)
        }
        if step == .target {
            primaryBtn.isEnabled = reason == nil
        }
        return reason == nil
    }

    func refreshUSB() {
        if running { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let mux = Self.run("/bin/bash", ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; if [ -x \(kIdevice) ]; then \(kIdevice) -l; else idevice_id -l; fi"])
            let muxIDs = mux.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.isEmpty && !$0.contains("ERROR") && !$0.contains("No device") }
            let ioreg = Self.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0"])
            let usbPhone = ioreg.range(of: "iPhone", options: .caseInsensitive) != nil
            let en9 = Self.run("/sbin/ifconfig", ["en9"])
            let en9Up = en9.contains("status: active")
            let probe = Self.run("/usr/bin/python3", [kPreservePy, "probe"])
            var badge = ""
            var color = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.25, alpha: 1)
            if !muxIDs.isEmpty {
                let names = muxIDs.map { $0.lowercased() == kBabyUDID ? "\($0) (GrokBotBaby)" : $0 }.joined(separator: ", ")
                badge = "USB ready — mux \(names)"
                color = NSColor(srgbRed: 0.45, green: 0.78, blue: 0.52, alpha: 1)
            } else if usbPhone && muxIDs.isEmpty && en9Up {
                badge = "Personal Hotspot has the cable — turn hotspot off, unlock, Trust"
                color = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.25, alpha: 1)
            } else if usbPhone && muxIDs.isEmpty {
                badge = "iPhone on USB, usbmux empty — unlock and Trust"
            } else {
                badge = "no phone on USB — plug GrokBotBaby, unlock, Trust"
            }
            var detail = "mux: \(muxIDs.isEmpty ? "(empty)" : muxIDs.joined(separator: " "))"
            detail += "  ·  USB iPhone node: \(usbPhone ? "present" : "absent")"
            detail += "  ·  en9: \(en9Up ? "up" : "down")"
            if let idx = probe.range(of: "{") {
                let tail = String(probe[idx.lowerBound...])
                if tail.count < 400 {
                    detail += "\nprobe: \(tail.replacingOccurrences(of: "\n", with: " "))"
                } else {
                    detail += "\nprobe: \(probe.split(separator: "\n").first.map(String.init) ?? "")"
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.usbBadge.stringValue = badge
                self.usbBadge.textColor = color
                self.usbDetail.stringValue = detail
            }
        }
    }

    func startBackup() {
        if running { return }
        if !validateDest(show: true) { return }
        if alias != "GrokBotBaby" && alias != "Brick" { return }
        stopWaiterIfNeeded()
        running = true
        applyStep()
        let dest = (destField.stringValue as NSString).expandingTildeInPath
        appendLog("\n—— \(isoNow())  python3 \(kPreservePy) all \(alias)\n")
        appendLog("FC_PRESERVE_ROOT=\(dest)\n")
        appendLog("waiter stopped if it was looping (app owns this run)\n\n")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [kPreservePy, "all", alias]
        var env = ProcessInfo.processInfo.environment
        env["FC_PRESERVE_ROOT"] = dest
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + path
        env["PYTHONUNBUFFERED"] = "1"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                self?.appendLog(s)
            }
        }
        task.terminationHandler = { [weak self] t in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.appendLog("\n—— exit \(t.terminationStatus)\n")
                self.running = false
                self.proc = nil
                self.flashBtn.isEnabled = false
                self.flashBtn.title = "flash locked (gate not ready)"
                self.applyStep()
            }
        }
        do {
            try task.run()
            proc = task
        } catch {
            appendLog("failed to start preserve.py: \(error)\n")
            running = false
            applyStep()
        }
    }

    func stopWaiterIfNeeded() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", kWaiterNeedle]
        try? p.run()
        p.waitUntilExit()
    }

    func appendLog(_ s: String) {
        let work = {
            let end = NSRange(location: self.logView.string.utf16.count, length: 0)
            self.logView.replaceCharacters(in: end, with: s)
            let last = NSRange(location: max(0, self.logView.string.utf16.count - 1), length: 1)
            self.logView.scrollRangeToVisible(last)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f.string(from: Date())
    }

    static func run(_ path: String, _ args: [String]) -> String {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: path)
        t.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        t.environment = env
        let pipe = Pipe()
        t.standardOutput = pipe
        t.standardError = pipe
        do { try t.run() } catch { return "err \(error)" }
        let deadline = Date().addingTimeInterval(6)
        while t.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if t.isRunning { t.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        if let proc = proc, proc.isRunning { proc.terminate() }
    }
}

func logApp(_ s: String) {
    let line = s + "\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/fc-preserve-app.log")
        if FileManager.default.fileExists(atPath: url.path) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

private let gDelegate = AppDelegate()

func installMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About FC-Preserve", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Quit FC-Preserve", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem()
    menu.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    NSApp.mainMenu = menu
}

logApp("main start screens=\(NSScreen.screens.count)")
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = gDelegate
installMenu()
app.activate(ignoringOtherApps: true)
app.run()
