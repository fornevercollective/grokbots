import Cocoa
import Foundation

let kPreservePy = "/Volumes/qbitOS/00.dev/grokbotsGH/fc-preserve/preserve.py"
let kDefaultVault = "/Volumes/MacBookPro - Data/FC-Preserve"
let kIdevice = "/opt/homebrew/bin/idevice_id"
let kBabyUDID = "4ea7e05b3045f0e9036275125a85225dd6dd9bb9"
let kBabySerial = "FCDTR1N8HFY7"
let kWaiterNeedle = "fc-preserve-wait.sh"
let kMotionURL = "https://live.ugrad.ai/motion"
let kBlochURL = "http://127.0.0.1:8793"
let kBridgeURL = "http://127.0.0.1:8798"
let kTokenPath = NSHomeDirectory() + "/.machines/hub.token"
let kPhotoLibraryFloor: Int64 = 300 * 1024 * 1024 * 1024
let kInternalFreeFloor: Int64 = 50 * 1024 * 1024 * 1024

enum WizardStep: Int {
    case device = 1
    case target = 2
    case backup = 3
}

struct DriveRow {
    var name: String
    var mount: String
    var size: Int64
    var used: Int64
    var free: Int64
    var pct: Int
    var fs: String
    var kind: String
}

final class Theme {
    static let bg = NSColor(srgbRed: 0.102, green: 0.110, blue: 0.125, alpha: 1)
    static let card = NSColor(srgbRed: 0.145, green: 0.157, blue: 0.176, alpha: 1)
    static let inset = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
    static let dim = NSColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1)
    static let mute = NSColor(srgbRed: 0.50, green: 0.52, blue: 0.56, alpha: 1)
    static let text = NSColor.white
    static let accent = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.16, alpha: 1)
    static let ok = NSColor(srgbRed: 0.45, green: 0.78, blue: 0.52, alpha: 1)
    static let warn = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.25, alpha: 1)
    static let bad = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.38, alpha: 1)
    static let usedBar = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.16, alpha: 1)
    static let freeBar = NSColor(srgbRed: 0.28, green: 0.55, blue: 0.40, alpha: 1)
    static let stepOff = NSColor(srgbRed: 0.28, green: 0.30, blue: 0.34, alpha: 1)
}

func fmtBytes(_ n: Int64) -> String {
    if n <= 0 { return "0" }
    let d = Double(n)
    let ti = 1024.0 * 1024 * 1024 * 1024
    let gi = 1024.0 * 1024 * 1024
    let mi = 1024.0 * 1024
    if d >= ti { return String(format: "%.1f Ti", d / ti) }
    if d >= gi { return String(format: "%.0f Gi", d / gi) }
    if d >= mi { return String(format: "%.0f Mi", d / mi) }
    return String(format: "%.0f B", d)
}

func lab(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, wrap: Bool = false) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = NSFont.systemFont(ofSize: size, weight: weight)
    t.textColor = color
    t.translatesAutoresizingMaskIntoConstraints = false
    return t
}

func mono(_ s: String, size: CGFloat, color: NSColor, wrap: Bool = false) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    t.textColor = color
    t.translatesAutoresizingMaskIntoConstraints = false
    return t
}

func symbolView(_ name: String, size: CGFloat = 14) -> NSImageView {
    let v = NSImageView()
    v.translatesAutoresizingMaskIntoConstraints = false
    if #available(macOS 11.0, *) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        v.image = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(cfg)
    }
    v.contentTintColor = Theme.accent
    v.imageScaling = .scaleProportionallyUpOrDown
    NSLayoutConstraint.activate([
        v.widthAnchor.constraint(equalToConstant: size + 4),
        v.heightAnchor.constraint(equalToConstant: size + 4),
    ])
    return v
}

final class StackBarView: NSView {
    var used: Double = 0
    var free: Double = 0
    var unknown: Bool = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = Theme.inset.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let r = bounds.insetBy(dx: 1, dy: 1)
        Theme.inset.setFill()
        NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
        let total = used + free
        if unknown || total <= 0 { return }
        let usedW = max(0, min(r.width, r.width * CGFloat(used / total)))
        if usedW > 0.5 {
            Theme.usedBar.setFill()
            let ur = NSRect(x: r.minX, y: r.minY, width: usedW, height: r.height)
            NSBezierPath(roundedRect: ur, xRadius: 4, yRadius: 4).fill()
        }
        if usedW < r.width - 1 {
            Theme.freeBar.setFill()
            let fr = NSRect(x: r.minX + usedW, y: r.minY, width: r.width - usedW, height: r.height)
            NSBezierPath(rect: fr).fill()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let ui = PreserveWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logApp("didFinishLaunching screens=\(NSScreen.screens.count)")
        if ui.window == nil { ui.build() }
        ui.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.ui.show()
            logApp("async show visible=\(self.ui.window.isVisible) frame=\(self.ui.window.frame)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
}

final class PreserveWindow: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var window: NSWindow!
    var step: WizardStep = .device
    var alias = "GrokBotBaby"
    var running = false
    var proc: Process?
    var timer: Timer?
    var deskBusy = false

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

    var drivesView: NSTextView!
    var flagsView: NSTextView!
    var drivePopup: NSPopUpButton!
    var driveBar: StackBarView!
    var driveBarCap: NSTextField!
    var phoneBar: StackBarView!
    var phoneBarCap: NSTextField!
    var partCamera: NSTextField!
    var partSensors: NSTextField!
    var partStorage: NSTextField!
    var partIDs: NSTextField!
    var routesStack: NSStackView!
    var motionStatus: NSTextField!
    var motionRoute: NSTextField!
    var captureNote: NSTextField!
    var captureBtn: NSButton!
    var openMotionBtn: NSButton!
    var copyMotionBtn: NSButton!
    var openBlochBtn: NSButton!

    var lastDrives: [DriveRow] = []
    var lastMux: [String] = []
    var lastHotspot = false
    var lastMuxEmpty = true
    var selectedMount = "/Volumes/MacBookPro - Data"
    var captureReady = false
    var blochUp = false

    func build() {
        let rect = NSRect(x: 0, y: 0, width: 1280, height: 860)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FC-Preserve"
        window.minSize = NSSize(width: 1100, height: 720)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()

        let root = NSView(frame: rect)
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.bg.cgColor
        window.contentView = root

        let header = lab("FC-Preserve", size: 22, weight: .semibold, color: Theme.text)
        let sub = lab("desk  ·  backup  ·  extract  ·  catalog  ·  SHA-256  ·  gate", size: 12, weight: .regular, color: Theme.dim)
        root.addSubview(header)
        root.addSubview(sub)

        let stepper = makeStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stepper)

        card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.card.cgColor
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
                pane.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
                pane.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
                pane.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
                pane.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            ])
        }

        let desk = makeDeskPane()
        desk.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(desk)

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

        footNote = lab("Never flashes. linux / Etcher stay off until gate.ready. Desk is live inventory + tether.", size: 11, weight: .regular, color: Theme.mute)
        footNote.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footNote)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            sub.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            sub.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            stepper.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 12),
            stepper.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stepper.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stepper.heightAnchor.constraint(equalToConstant: 40),
            card.topAnchor.constraint(equalTo: stepper.bottomAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            card.widthAnchor.constraint(equalToConstant: 420),
            card.bottomAnchor.constraint(equalTo: primaryBtn.topAnchor, constant: -14),
            desk.topAnchor.constraint(equalTo: stepper.bottomAnchor, constant: 12),
            desk.leadingAnchor.constraint(equalTo: card.trailingAnchor, constant: 12),
            desk.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            desk.bottomAnchor.constraint(equalTo: primaryBtn.topAnchor, constant: -14),
            primaryBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            primaryBtn.bottomAnchor.constraint(equalTo: footNote.topAnchor, constant: -8),
            primaryBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 168),
            primaryBtn.heightAnchor.constraint(equalToConstant: 36),
            backBtn.trailingAnchor.constraint(equalTo: primaryBtn.leadingAnchor, constant: -10),
            backBtn.centerYAnchor.constraint(equalTo: primaryBtn.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 88),
            backBtn.heightAnchor.constraint(equalToConstant: 36),
            flashBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            flashBtn.centerYAnchor.constraint(equalTo: primaryBtn.centerYAnchor),
            flashBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            flashBtn.heightAnchor.constraint(equalToConstant: 36),
            footNote.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footNote.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])

        applyStep()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func show() {
        let screen = NSScreen.screens.first ?? NSScreen.main
        if let screen = screen {
            let vis = screen.visibleFrame
            let size = NSSize(width: min(1280, vis.width - 40), height: min(860, vis.height - 40))
            let origin = NSPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        logApp("show frame=\(window.frame) screen=\(String(describing: window.screen?.localizedName))")
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
            let titleLab = NSTextField(labelWithString: title)
            titleLab.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            titleLab.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(titleLab)
            stepLabels.append(titleLab)
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
                titleLab.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
                titleLab.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                titleLab.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
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
        let title = lab("SELECT DEVICE", size: 16, weight: .semibold, color: Theme.text)
        v.addSubview(title)
        babyRadio = NSButton(radioButtonWithTitle: "GrokBotBaby     iPhone 7 Plus · A10 checkm8 · default", target: self, action: #selector(pickDevice(_:)))
        babyRadio.state = .on
        babyRadio.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        babyRadio.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(babyRadio)
        brickRadio = NSButton(radioButtonWithTitle: "Brick     daily iPhone · Continuity · never flash", target: self, action: #selector(pickDevice(_:)))
        brickRadio.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        brickRadio.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(brickRadio)
        deviceHint = lab("GrokBotBaby — iPhone9,4 D111AP iOS 15.1. Preserve everything locally. Flash stays locked until linux-gate.json ready.", size: 12, weight: .regular, color: Theme.dim, wrap: true)
        v.addSubview(deviceHint)
        usbBadge = lab("USB: probing…", size: 13, weight: .semibold, color: Theme.warn, wrap: true)
        v.addSubview(usbBadge)
        usbDetail = mono("", size: 11, color: Theme.dim, wrap: true)
        v.addSubview(usbDetail)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            babyRadio.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            babyRadio.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            babyRadio.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),
            brickRadio.topAnchor.constraint(equalTo: babyRadio.bottomAnchor, constant: 8),
            brickRadio.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            deviceHint.topAnchor.constraint(equalTo: brickRadio.bottomAnchor, constant: 12),
            deviceHint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            deviceHint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            usbBadge.topAnchor.constraint(equalTo: deviceHint.bottomAnchor, constant: 16),
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
        let title = lab("SELECT TARGET", size: 16, weight: .semibold, color: Theme.text)
        v.addSubview(title)
        let hint = lab("Vault root for backup → extract → catalog → SHA-256 → linux-gate.json. Not Internal. Not the lab SSD.", size: 12, weight: .regular, color: Theme.dim, wrap: true)
        v.addSubview(hint)
        destField = NSTextField(string: kDefaultVault)
        destField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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
        destError = lab("", size: 12, weight: .medium, color: Theme.bad, wrap: true)
        v.addSubview(destError)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            destField.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
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
        let title = lab("BACKUP + verify", size: 16, weight: .semibold, color: Theme.text)
        v.addSubview(title)
        let hint = lab("Runs preserve.py all <alias> only. Streams stdout here. Does not call linux. Does not flash.", size: 12, weight: .regular, color: Theme.dim, wrap: true)
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
        logView.backgroundColor = Theme.inset
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

    private func sectionTitle(_ title: String, symbol: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let ic = symbolView(symbol, size: 13)
        let t = lab(title, size: 12, weight: .semibold, color: Theme.accent)
        row.addSubview(ic)
        row.addSubview(t)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
            ic.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            ic.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            t.leadingAnchor.constraint(equalTo: ic.trailingAnchor, constant: 6),
            t.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            t.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    private func makeTextBox(_ height: CGFloat) -> (NSScrollView, NSTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 6
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.inset
        let tv = NSTextView()
        tv.isEditable = false
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tv.backgroundColor = Theme.inset
        tv.textColor = NSColor(srgbRed: 0.82, green: 0.86, blue: 0.80, alpha: 1)
        tv.autoresizingMask = [.width, .height]
        tv.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = tv
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return (scroll, tv)
    }

    private func partCard(symbol: String, title: String, body: inout NSTextField!) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.inset.cgColor
        box.layer?.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false
        let ic = symbolView(symbol, size: 15)
        let t = lab(title, size: 11, weight: .semibold, color: Theme.text)
        body = lab("…", size: 10.5, weight: .regular, color: Theme.dim, wrap: true)
        box.addSubview(ic)
        box.addSubview(t)
        box.addSubview(body)
        NSLayoutConstraint.activate([
            ic.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            ic.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            t.centerYAnchor.constraint(equalTo: ic.centerYAnchor),
            t.leadingAnchor.constraint(equalTo: ic.trailingAnchor, constant: 6),
            body.topAnchor.constraint(equalTo: ic.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
        ])
        return box
    }

    private func makeDeskPane() -> NSView {
        let wrap = NSView()
        wrap.wantsLayer = true
        wrap.layer?.backgroundColor = Theme.card.cgColor
        wrap.layer?.cornerRadius = 12

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(scroll)

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let h1 = sectionTitle("ALL PLUGGED DRIVES", symbol: "internaldrive")
        let (drvScroll, drvTV) = makeTextBox(148)
        drivesView = drvTV
        drivesView.string = "diskutil + df probing…"
        doc.addSubview(h1)
        doc.addSubview(drvScroll)

        let flagsBox = NSTextView()
        flagsBox.isEditable = false
        flagsBox.isRichText = false
        flagsBox.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        flagsBox.backgroundColor = Theme.inset
        flagsBox.textColor = Theme.warn
        flagsBox.autoresizingMask = [.width, .height]
        flagsBox.textContainerInset = NSSize(width: 6, height: 4)
        flagsView = flagsBox
        let flagsScroll = NSScrollView()
        flagsScroll.translatesAutoresizingMaskIntoConstraints = false
        flagsScroll.hasVerticalScroller = true
        flagsScroll.borderType = .bezelBorder
        flagsScroll.drawsBackground = true
        flagsScroll.backgroundColor = Theme.inset
        flagsScroll.documentView = flagsBox
        flagsScroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        doc.addSubview(flagsScroll)

        let h2 = sectionTitle("PARTS", symbol: "cpu")
        doc.addSubview(h2)
        var cam: NSTextField!
        var sen: NSTextField!
        var sto: NSTextField!
        var ids: NSTextField!
        let c1 = partCard(symbol: "camera.fill", title: "CAMERA", body: &cam)
        let c2 = partCard(symbol: "gyroscope", title: "SENSORS", body: &sen)
        let c3 = partCard(symbol: "sdcard", title: "STORAGE", body: &sto)
        let c4 = partCard(symbol: "barcode", title: "UNIQUE IDs", body: &ids)
        partCamera = cam
        partSensors = sen
        partStorage = sto
        partIDs = ids
        let parts = NSStackView(views: [c1, c2, c3, c4])
        parts.orientation = .horizontal
        parts.distribution = .fillEqually
        parts.spacing = 8
        parts.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(parts)

        let h3 = sectionTitle("STORAGE DISTRIBUTION", symbol: "chart.bar.fill")
        doc.addSubview(h3)
        drivePopup = NSPopUpButton()
        drivePopup.translatesAutoresizingMaskIntoConstraints = false
        drivePopup.target = self
        drivePopup.action = #selector(drivePicked)
        drivePopup.addItem(withTitle: "MacBookPro - Data")
        doc.addSubview(drivePopup)
        driveBar = StackBarView(frame: .zero)
        driveBar.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(driveBar)
        driveBarCap = mono("used / free — probing", size: 10.5, color: Theme.dim, wrap: true)
        doc.addSubview(driveBarCap)
        phoneBar = StackBarView(frame: .zero)
        phoneBar.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(phoneBar)
        phoneBarCap = mono("phone 0 / unknown — mux empty", size: 10.5, color: Theme.dim, wrap: true)
        doc.addSubview(phoneBarCap)

        let h4 = sectionTitle("FILE + TERMINAL ROUTES", symbol: "terminal")
        doc.addSubview(h4)
        routesStack = NSStackView()
        routesStack.orientation = .vertical
        routesStack.alignment = .leading
        routesStack.spacing = 3
        routesStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(routesStack)

        let h5 = sectionTitle("MOTION / TETHER", symbol: "wifi")
        doc.addSubview(h5)
        motionStatus = lab("token / page / Bloch — probing", size: 11, weight: .medium, color: Theme.dim, wrap: true)
        doc.addSubview(motionStatus)
        motionRoute = mono("https://live.ugrad.ai/motion   ·   Bloch http://127.0.0.1:8793   ·   capture → vault/<alias>/<stamp>/motion/", size: 10.5, color: Theme.dim, wrap: true)
        doc.addSubview(motionRoute)

        openMotionBtn = button("Open live motion", filled: false, action: #selector(openMotion))
        copyMotionBtn = button("Copy URL", filled: false, action: #selector(copyMotion))
        openBlochBtn = button("Bloch viewer", filled: false, action: #selector(openBloch))
        captureBtn = button("Capture frame", filled: true, action: #selector(captureMotion))
        openMotionBtn.translatesAutoresizingMaskIntoConstraints = false
        copyMotionBtn.translatesAutoresizingMaskIntoConstraints = false
        openBlochBtn.translatesAutoresizingMaskIntoConstraints = false
        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        openBlochBtn.isEnabled = false
        captureBtn.isHidden = true
        let btnRow = NSStackView(views: [openMotionBtn, copyMotionBtn, openBlochBtn, captureBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(btnRow)
        captureNote = lab("not capturing yet — no live.jpg / AFC mount / Continuity pipe. idevicescreenshot waits for mux.", size: 11, weight: .regular, color: Theme.warn, wrap: true)
        doc.addSubview(captureNote)

        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            h1.topAnchor.constraint(equalTo: doc.topAnchor, constant: pad),
            h1.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            h1.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            drvScroll.topAnchor.constraint(equalTo: h1.bottomAnchor, constant: 6),
            drvScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            drvScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            flagsScroll.topAnchor.constraint(equalTo: drvScroll.bottomAnchor, constant: 6),
            flagsScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            flagsScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            h2.topAnchor.constraint(equalTo: flagsScroll.bottomAnchor, constant: 14),
            h2.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            h2.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            parts.topAnchor.constraint(equalTo: h2.bottomAnchor, constant: 6),
            parts.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            parts.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            parts.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            h3.topAnchor.constraint(equalTo: parts.bottomAnchor, constant: 14),
            h3.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            drivePopup.topAnchor.constraint(equalTo: h3.bottomAnchor, constant: 6),
            drivePopup.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            drivePopup.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            driveBar.topAnchor.constraint(equalTo: drivePopup.bottomAnchor, constant: 6),
            driveBar.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            driveBar.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            driveBar.heightAnchor.constraint(equalToConstant: 18),
            driveBarCap.topAnchor.constraint(equalTo: driveBar.bottomAnchor, constant: 4),
            driveBarCap.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            driveBarCap.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            phoneBar.topAnchor.constraint(equalTo: driveBarCap.bottomAnchor, constant: 8),
            phoneBar.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            phoneBar.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            phoneBar.heightAnchor.constraint(equalToConstant: 18),
            phoneBarCap.topAnchor.constraint(equalTo: phoneBar.bottomAnchor, constant: 4),
            phoneBarCap.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            phoneBarCap.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            h4.topAnchor.constraint(equalTo: phoneBarCap.bottomAnchor, constant: 14),
            h4.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            routesStack.topAnchor.constraint(equalTo: h4.bottomAnchor, constant: 6),
            routesStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            routesStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            h5.topAnchor.constraint(equalTo: routesStack.bottomAnchor, constant: 14),
            h5.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            motionStatus.topAnchor.constraint(equalTo: h5.bottomAnchor, constant: 6),
            motionStatus.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            motionStatus.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            motionRoute.topAnchor.constraint(equalTo: motionStatus.bottomAnchor, constant: 4),
            motionRoute.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            motionRoute.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            btnRow.topAnchor.constraint(equalTo: motionRoute.bottomAnchor, constant: 8),
            btnRow.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            captureNote.topAnchor.constraint(equalTo: btnRow.bottomAnchor, constant: 6),
            captureNote.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            captureNote.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            captureNote.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -18),
        ])
        return wrap
    }

    private func button(_ title: String, filled: Bool, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: action == nil ? nil : self, action: action)
        b.bezelStyle = .rounded
        if filled {
            if #available(macOS 11.0, *) { b.controlSize = .large }
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
        for (i, dot) in stepDots.enumerated() {
            let on = (i + 1) == step.rawValue
            dot.layer?.backgroundColor = (on ? Theme.accent : Theme.stepOff).cgColor
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
            deviceHint.stringValue = "Brick is the daily Continuity iPhone — preserve only, never flash."
        } else {
            alias = "GrokBotBaby"
            babyRadio.state = .on
            brickRadio.state = .off
            deviceHint.stringValue = "GrokBotBaby — iPhone9,4 D111AP A10 checkm8 iOS 15.1. Preserve everything locally. Flash stays locked until linux-gate.json ready."
        }
        applyParts(phoneUsed: 0, phoneFree: 0, phoneKnown: false)
    }

    @objc func goBack() {
        if running { return }
        if step == .backup { step = .target }
        else if step == .target { step = .device }
        applyStep()
    }

    @objc func goNext() {
        if step == .device { step = .target; applyStep(); return }
        if step == .target {
            if validateDest(show: true) {
                step = .backup
                applyStep()
                appendLog("Target: \(destField.stringValue)\nDevice: \(alias)\n")
            }
            return
        }
        if step == .backup { startBackup() }
    }

    @objc func destChanged() {
        _ = validateDest(show: true)
        if step == .target { primaryBtn.isEnabled = validateDest(show: false) }
    }

    func controlTextDidChange(_ obj: Notification) { destChanged() }

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
        } else if expanded == docs || expanded.hasPrefix(docs + "/") || (expanded.contains("/Documents/FC-Preserve") && expanded.hasPrefix(home)) {
            reason = "Refuse ~/Documents — Internal too tight. Use /Volumes/MacBookPro - Data/FC-Preserve."
        } else if expanded.hasPrefix("/Users/") && expanded.contains("/Documents") {
            reason = "Refuse ~/Documents — Internal too tight. Use /Volumes/MacBookPro - Data/FC-Preserve."
        }
        if show {
            destError.stringValue = reason ?? "OK — vault on the Data volume."
            destError.textColor = reason == nil ? Theme.ok : Theme.bad
        }
        if step == .target { primaryBtn.isEnabled = reason == nil }
        return reason == nil
    }

    @objc func drivePicked() {
        guard let title = drivePopup.selectedItem?.title else { return }
        if let row = lastDrives.first(where: { $0.name == title || $0.mount == title }) {
            selectedMount = row.mount
            applyDriveBar(row)
        }
    }

    @objc func openMotion() {
        if let url = URL(string: kMotionURL) { NSWorkspace.shared.open(url) }
    }

    @objc func copyMotion() { copyString(kMotionURL) }

    @objc func openBloch() {
        if blochUp, let url = URL(string: kBlochURL) { NSWorkspace.shared.open(url) }
    }

    func copyString(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    @objc func copyRoute(_ sender: NSButton) {
        if let path = sender.toolTip, !path.isEmpty { copyString(path) }
    }

    @objc func captureMotion() {
        if !captureReady { return }
        let dest = motionDestDir()
        do {
            try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        } catch {
            captureNote.stringValue = "could not create \(dest): \(error)"
            captureNote.textColor = Theme.bad
            return
        }
        let shot = dest + "/live.jpg"
        let out = Self.run("/opt/homebrew/bin/idevicescreenshot", [shot])
        if FileManager.default.fileExists(atPath: shot) {
            captureNote.stringValue = "captured \(shot)"
            captureNote.textColor = Theme.ok
            appendLog("motion capture: \(shot)\n")
        } else {
            captureNote.stringValue = "not capturing — idevicescreenshot failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
            captureNote.textColor = Theme.bad
        }
    }

    func motionDestDir() -> String {
        let vault = (destField.stringValue as NSString).expandingTildeInPath
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return vault + "/" + alias + "/" + f.string(from: Date()) + "/motion"
    }

    func refreshAll() {
        if running { return }
        if deskBusy { return }
        deskBusy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let snap = self.collectSnap()
            DispatchQueue.main.async {
                self.applySnap(snap)
                self.deskBusy = false
            }
        }
    }

    struct Snap {
        var mux: [String]
        var usbPhone: Bool
        var en9Up: Bool
        var drives: [DriveRow]
        var diskutilHead: String
        var tokenPresent: Bool
        var pageCode: String
        var blochCode: String
        var bridgeCode: String
        var phoneUsed: Int64
        var phoneFree: Int64
        var phoneKnown: Bool
        var tools: [(String, String, String, Bool, String)]
        var latestStamp: String
        var vaultExists: Bool
        var liveJpg: Bool
        var afcUp: Bool
    }

    func collectSnap() -> Snap {
        let muxRaw = Self.run("/bin/bash", ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; if [ -x \(kIdevice) ]; then \(kIdevice) -l; else idevice_id -l; fi"])
        let mux = muxRaw.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.isEmpty && !$0.contains("ERROR") && !$0.contains("No device") }
        let ioreg = Self.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0"])
        let usbPhone = ioreg.range(of: "iPhone", options: .caseInsensitive) != nil
        let en9 = Self.run("/sbin/ifconfig", ["en9"])
        let en9Up = en9.contains("status: active")
        let df = Self.run("/bin/df", ["-P", "-k"])
        let mount = Self.run("/sbin/mount", [])
        let dlist = Self.run("/usr/sbin/diskutil", ["list"])
        let drives = Self.parseDrives(df: df, mount: mount)
        let diskHead = dlist.split(separator: "\n").prefix(8).joined(separator: "\n")
        let tokenPresent = FileManager.default.fileExists(atPath: kTokenPath)
        let pageCode = Self.httpCode(kMotionURL)
        let blochCode = Self.httpCode(kBlochURL + "/")
        let bridgeCode = Self.httpCode(kBridgeURL + "/")
        var phoneUsed: Int64 = 0
        var phoneFree: Int64 = 0
        var phoneKnown = false
        if !mux.isEmpty {
            let cap = Self.ideviceKey("TotalDiskCapacity")
            let avail = Self.ideviceKey("TotalDataAvailable")
            if let c = Int64(cap), c > 0 {
                phoneKnown = true
                phoneUsed = 0
                phoneFree = 0
                if let a = Int64(avail), a >= 0 {
                    phoneFree = a
                    phoneUsed = max(0, c - a)
                } else {
                    phoneUsed = c
                }
            }
        }
        let tools = self.toolRoutes()
        let latest = self.latestStampPath()
        let vaultExists = FileManager.default.fileExists(atPath: kDefaultVault)
        let liveJpg = FileManager.default.fileExists(atPath: "/tmp/live.jpg")
        return Snap(
            mux: mux, usbPhone: usbPhone, en9Up: en9Up, drives: drives, diskutilHead: diskHead,
            tokenPresent: tokenPresent, pageCode: pageCode, blochCode: blochCode, bridgeCode: bridgeCode,
            phoneUsed: phoneUsed, phoneFree: phoneFree, phoneKnown: phoneKnown, tools: tools,
            latestStamp: latest, vaultExists: vaultExists, liveJpg: liveJpg, afcUp: false
        )
    }

    func applySnap(_ s: Snap) {
        lastDrives = s.drives
        lastMux = s.mux
        lastHotspot = s.usbPhone && s.mux.isEmpty && s.en9Up
        lastMuxEmpty = s.mux.isEmpty
        blochUp = s.blochCode != "000" && !s.blochCode.isEmpty

        var badge = ""
        var color = Theme.warn
        if !s.mux.isEmpty {
            let names = s.mux.map { $0.lowercased() == kBabyUDID ? "\($0) (GrokBotBaby)" : $0 }.joined(separator: ", ")
            badge = "USB ready — mux \(names)"
            color = Theme.ok
        } else if s.usbPhone && s.mux.isEmpty && s.en9Up {
            badge = "Personal Hotspot has the cable — turn hotspot off, unlock, Trust"
        } else if s.usbPhone && s.mux.isEmpty {
            badge = "iPhone on USB, usbmux empty — unlock and Trust"
        } else {
            badge = "no phone on USB — plug GrokBotBaby, unlock, Trust"
        }
        usbBadge.stringValue = badge
        usbBadge.textColor = color
        var detail = "mux: \(s.mux.isEmpty ? "(empty)" : s.mux.joined(separator: " "))"
        detail += "  ·  USB iPhone node: \(s.usbPhone ? "present" : "absent")"
        detail += "  ·  en9: \(s.en9Up ? "up" : "down")"
        usbDetail.stringValue = detail

        var lines = "NAME                    MOUNT                          SIZE     USED     FREE   %   FS"
        for d in s.drives {
            let name = d.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            let mnt = d.mount.padding(toLength: 30, withPad: " ", startingAt: 0)
            lines += "\n\(name) \(mnt) \(padR(fmtBytes(d.size), 7)) \(padR(fmtBytes(d.used), 7)) \(padR(fmtBytes(d.free), 7)) \(String(format: "%3d", d.pct))%  \(d.fs)"
        }
        if s.usbPhone && !s.drives.contains(where: { $0.kind == "phone" }) {
            lines += "\nUSB iPhone              (no filesystem mount)          0        0        0     0   —"
        }
        drivesView.string = lines

        var flags: [String] = []
        if let internalDrive = s.drives.first(where: { $0.kind == "internal" }) {
            if internalDrive.free < kInternalFreeFloor || internalDrive.pct >= 80 {
                flags.append("Internal tight — \(fmtBytes(internalDrive.free)) free (\(internalDrive.pct)%). Use the Data vault, not ~/Documents.")
            }
        }
        if !s.vaultExists {
            flags.append("vault missing — \(kDefaultVault) is not on disk. Mount MacBookPro - Data, then mkdir -p that path.")
        }
        if let vaultVol = s.drives.first(where: { $0.mount == "/Volumes/MacBookPro - Data" }) {
            if vaultVol.free < kPhotoLibraryFloor {
                flags.append("vault free too small for a big photo library — \(fmtBytes(vaultVol.free)) on MacBookPro - Data (need ≥ 300 Gi).")
            }
        } else if s.vaultExists == false {
            flags.append("dest volume MacBookPro - Data is not mounted.")
        }
        if lastHotspot {
            flags.append("Personal Hotspot has the cable — turn hotspot off, unlock, Trust.")
        } else if s.usbPhone && s.mux.isEmpty {
            flags.append("mux empty — unlock the phone and tap Trust.")
        }
        if destField != nil && !validateDest(show: false) {
            flags.append("dest refused — \(destError.stringValue)")
        }
        if flags.isEmpty { flags.append("no capacity / mux flags.") }
        flagsView.string = flags.map { "• \($0)" }.joined(separator: "\n")
        flagsView.textColor = flags.contains(where: { $0.contains("Hotspot") || $0.contains("missing") || $0.contains("refused") }) ? Theme.bad : Theme.warn

        let keep = selectedMount
        drivePopup.removeAllItems()
        for d in s.drives { drivePopup.addItem(withTitle: d.name) }
        if let idx = s.drives.firstIndex(where: { $0.mount == keep }) {
            drivePopup.selectItem(at: idx)
            applyDriveBar(s.drives[idx])
        } else if let vault = s.drives.first(where: { $0.mount == "/Volumes/MacBookPro - Data" }) {
            selectedMount = vault.mount
            if let idx = s.drives.firstIndex(where: { $0.mount == vault.mount }) { drivePopup.selectItem(at: idx) }
            applyDriveBar(vault)
        } else if let first = s.drives.first {
            selectedMount = first.mount
            applyDriveBar(first)
        }

        applyParts(phoneUsed: s.phoneUsed, phoneFree: s.phoneFree, phoneKnown: s.phoneKnown)
        applyPhoneBar(used: s.phoneUsed, free: s.phoneFree, known: s.phoneKnown, mux: s.mux)
        rebuildRoutes(s)
        applyMotion(s)
    }

    func applyDriveBar(_ d: DriveRow) {
        driveBar.unknown = d.size <= 0 && d.used <= 0 && d.free <= 0
        driveBar.used = Double(d.used)
        driveBar.free = Double(d.free)
        driveBar.needsDisplay = true
        if driveBar.unknown {
            driveBarCap.stringValue = "\(d.name)  used 0 / free 0 — unknown"
        } else {
            driveBarCap.stringValue = "\(d.name)  used \(fmtBytes(d.used)) / free \(fmtBytes(d.free)) / \(d.pct)%   \(d.mount)"
        }
    }

    func applyPhoneBar(used: Int64, free: Int64, known: Bool, mux: [String]) {
        phoneBar.unknown = !known
        phoneBar.used = Double(used)
        phoneBar.free = Double(free)
        phoneBar.needsDisplay = true
        if !mux.isEmpty && known {
            let pct = used + free > 0 ? Int((Double(used) / Double(used + free)) * 100.0) : 0
            phoneBarCap.stringValue = "phone  used \(fmtBytes(used)) / free \(fmtBytes(free)) / \(pct)%  (mux up)"
        } else if !mux.isEmpty {
            phoneBarCap.stringValue = "phone  used 0 / free 0 — capacity keys unknown (mux up, ideviceinfo empty)"
        } else {
            phoneBarCap.stringValue = "phone  used 0 / free 0 — unknown (mux empty)"
        }
    }

    func applyParts(phoneUsed: Int64, phoneFree: Int64, phoneKnown: Bool) {
        if alias == "Brick" {
            partCamera.stringValue = "Continuity Camera body. Live frame: none. Preserve only."
            partSensors.stringValue = "Daily iPhone sensors — not inventoried until mux."
            partStorage.stringValue = phoneKnown ? "used \(fmtBytes(phoneUsed)) / free \(fmtBytes(phoneFree))" : "0 / unknown — mux empty or not Brick"
            partIDs.stringValue = "UDID unknown until mux.\nSerial unknown until mux.\nIMEI / Find My never shown."
            return
        }
        partCamera.stringValue = "iPhone 7 Plus dual 12MP (wide + tele). Live frame: none."
        partSensors.stringValue = "Touch ID · barometer · gyro · accel · compass · proximity"
        if phoneKnown {
            partStorage.stringValue = "used \(fmtBytes(phoneUsed)) / free \(fmtBytes(phoneFree))"
        } else {
            partStorage.stringValue = "0 / unknown — mux empty, not guessing capacity"
        }
        partIDs.stringValue = "UDID \(kBabyUDID)\nSerial \(kBabySerial)\niPhone9,4 D111AP A10 · iOS 15.1\nIMEI / Find My never shown."
    }

    func rebuildRoutes(_ s: Snap) {
        for v in routesStack.arrangedSubviews {
            routesStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let vault = (destField.stringValue as NSString).expandingTildeInPath
        let stamp = s.latestStamp.isEmpty ? "<stamp>" : s.latestStamp
        let base = vault + "/" + alias + "/" + stamp
        var rows: [(String, String, String, Bool, String)] = [
            ("externaldrive.fill", "vault", vault, s.vaultExists, s.vaultExists ? "present" : "missing"),
            ("folder", "extract/", base + "/extract/", FileManager.default.fileExists(atPath: base + "/extract"), "parsed domains"),
            ("list.bullet.rectangle", "catalog/", base + "/catalog/", FileManager.default.fileExists(atPath: base + "/catalog"), "apps.json + Apps/"),
            ("number", "hashes", base + "/hashes.sha256", FileManager.default.fileExists(atPath: base + "/hashes.sha256"), "SHA-256 chain"),
        ]
        rows.append(contentsOf: s.tools)
        for r in rows {
            routesStack.addArrangedSubview(routeRow(symbol: r.0, title: r.1, path: r.2, present: r.3, note: r.4))
        }
    }

    func routeRow(symbol: String, title: String, path: String, present: Bool, note: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let ic = symbolView(symbol, size: 12)
        let t = lab(title, size: 11, weight: .semibold, color: Theme.text)
        t.setContentHuggingPriority(.required, for: .horizontal)
        let p = mono(path, size: 10.5, color: present ? Theme.ok : Theme.bad)
        p.lineBreakMode = .byTruncatingMiddle
        let n = lab(note, size: 10, weight: .regular, color: Theme.mute)
        n.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let copy = NSButton(title: "copy", target: self, action: #selector(copyRoute(_:)))
        copy.bezelStyle = .inline
        copy.font = NSFont.systemFont(ofSize: 10)
        copy.toolTip = path
        copy.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(ic)
        row.addSubview(t)
        row.addSubview(p)
        row.addSubview(n)
        row.addSubview(copy)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 22),
            ic.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            ic.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            t.leadingAnchor.constraint(equalTo: ic.trailingAnchor, constant: 6),
            t.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            t.widthAnchor.constraint(equalToConstant: 118),
            copy.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            copy.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copy.widthAnchor.constraint(equalToConstant: 48),
            p.leadingAnchor.constraint(equalTo: t.trailingAnchor, constant: 6),
            p.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            p.trailingAnchor.constraint(lessThanOrEqualTo: copy.leadingAnchor, constant: -8),
            n.leadingAnchor.constraint(equalTo: p.trailingAnchor, constant: 8),
            n.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            n.trailingAnchor.constraint(lessThanOrEqualTo: copy.leadingAnchor, constant: -4),
        ])
        return row
    }

    func applyMotion(_ s: Snap) {
        let token = s.tokenPresent ? "token file present" : "token file missing"
        let page = s.pageCode == "200" ? "page reachable (200)" : "page \(s.pageCode.isEmpty ? "down" : s.pageCode)"
        let viewer = blochUp ? "Bloch viewer 8793 up" : "Bloch viewer 8793 down (not starting Elffin)"
        let ingest = blochUp ? "Bloch ingest up" : "Bloch ingest down"
        let bridge = (s.bridgeCode != "000" && !s.bridgeCode.isEmpty) ? "origin_bridge :8798 up (gated, token not printed)" : "origin_bridge :8798 down"
        motionStatus.stringValue = "\(token)  ·  \(page)  ·  \(viewer)  ·  \(ingest)  ·  \(bridge)"
        motionStatus.textColor = s.pageCode == "200" ? Theme.ok : Theme.warn
        motionRoute.stringValue = "\(kMotionURL)   ·   Bloch \(kBlochURL)   ·   would land in \(kDefaultVault)/\(alias)/<stamp>/motion/\nShawk/LAN first — no baked laptop IP. posed frames + video for NeRF+; stills + hashes for OSINT."
        openBlochBtn.isEnabled = blochUp
        let shot = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/idevicescreenshot")
        captureReady = !s.mux.isEmpty && shot
        captureBtn.isHidden = !captureReady
        if captureReady {
            captureNote.stringValue = "mux up — Capture writes live.jpg via idevicescreenshot into the vault motion folder. Will not invent frames."
            captureNote.textColor = Theme.ok
        } else if s.liveJpg {
            captureNote.stringValue = "found /tmp/live.jpg but mux empty — showing route only, not capturing."
            captureNote.textColor = Theme.warn
        } else {
            captureNote.stringValue = "not capturing yet — no live.jpg / ifuse AFC mount / Continuity pipe. idevicescreenshot waits for mux. ifuse and pymobiledevice3 are missing."
            captureNote.textColor = Theme.warn
        }
    }

    func toolRoutes() -> [(String, String, String, Bool, String)] {
        let names: [(String, String, String)] = [
            ("cable.connector", "idevice_id", "idevice_id"),
            ("info.circle", "ideviceinfo", "ideviceinfo"),
            ("externaldrive.badge.timemachine", "idevicebackup2", "idevicebackup2"),
            ("externaldrive.badge.plus", "ideviceimagemounter", "ideviceimagemounter"),
            ("dot.radiowaves.left.and.right", "ifuse/AFC", "ifuse"),
            ("link", "afcclient", "afcclient"),
            ("chevron.left.forwardslash.chevron.right", "pymobiledevice3", "pymobiledevice3"),
            ("hammer", "preserve.py", kPreservePy),
            ("network", "ssh", "ssh"),
        ]
        var out: [(String, String, String, Bool, String)] = []
        for (sym, title, bin) in names {
            if bin.hasPrefix("/") {
                let ok = FileManager.default.isReadableFile(atPath: bin)
                out.append((sym, title, bin, ok, ok ? "python3 preserve.py" : "missing"))
                continue
            }
            let path = Self.which(bin)
            if bin == "ifuse" {
                let afc = Self.which("afcclient")
                let note = path == nil ? "missing — brew install ifuse  (afcclient \(afc == nil ? "also missing" : "present"))" : "present"
                out.append((sym, title, path ?? "(ifuse not on PATH)", path != nil, note))
            } else if bin == "pymobiledevice3" {
                out.append((sym, title, path ?? "(not on PATH)", path != nil, path != nil ? "present" : "missing — pip/brew not installed"))
            } else {
                out.append((sym, title, path ?? "(\(bin) not on PATH)", path != nil, path != nil ? "on PATH" : "missing"))
            }
        }
        let py = Self.which("python3") ?? "/usr/bin/python3"
        out.insert(("apple.terminal", "python3", py, true, "host python"), at: 7)
        return out
    }

    func latestStampPath() -> String {
        let root = ((destField?.stringValue ?? kDefaultVault) as NSString).expandingTildeInPath + "/" + alias
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return "" }
        let stamps = names.filter { $0.count >= 15 && $0.contains("T") }.sorted()
        return stamps.last ?? ""
    }

    static func parseDrives(df: String, mount: String) -> [DriveRow] {
        var fsByMount: [String: String] = [:]
        for line in mount.split(separator: "\n") {
            let s = String(line)
            guard s.contains(" on ") else { continue }
            let parts = s.components(separatedBy: " on ")
            if parts.count < 2 { continue }
            let rest = parts[1]
            let mnt = rest.components(separatedBy: " (").first ?? rest
            var fst = "—"
            if let r = rest.range(of: "(") {
                fst = String(rest[r.upperBound...]).components(separatedBy: ",").first ?? "—"
            }
            fsByMount[mnt] = fst
        }
        var byMount: [String: (Int64, Int64, Int64, Int)] = [:]
        for (i, line) in df.split(separator: "\n").enumerated() {
            if i == 0 { continue }
            let cols = String(line).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if cols.count < 6 { continue }
            let mnt = cols[5...].joined(separator: " ")
            let size = (Int64(cols[1]) ?? 0) * 1024
            let used = (Int64(cols[2]) ?? 0) * 1024
            let free = (Int64(cols[3]) ?? 0) * 1024
            let pct = Int(cols[4].replacingOccurrences(of: "%", with: "")) ?? 0
            byMount[mnt] = (size, used, free, pct)
        }
        let wanted: [(String, String, String)] = [
            ("Internal", "/", "internal"),
            ("Internal Data", "/System/Volumes/Data", "internal-data"),
            ("MacBookPro", "/Volumes/MacBookPro", "mbp"),
            ("MacBookPro - Data", "/Volumes/MacBookPro - Data", "vault"),
            ("qbitOS", "/Volumes/qbitOS", "lab"),
        ]
        var rows: [DriveRow] = []
        var seen = Set<String>()
        for (name, mnt, kind) in wanted {
            if let t = byMount[mnt] {
                rows.append(DriveRow(name: name, mount: mnt, size: t.0, used: t.1, free: t.2, pct: t.3, fs: fsByMount[mnt] ?? "apfs", kind: kind))
                seen.insert(mnt)
            }
        }
        // other /Volumes mounts (USB phones, extra disks)
        if let volNames = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for name in volNames.sorted() {
                let mnt = "/Volumes/" + name
                if seen.contains(mnt) { continue }
                if name == "Macintosh HD" { continue }
                if let t = byMount[mnt] {
                    let lname = name.lowercased()
                    let kind = (lname.contains("iphone") || lname.contains("dcim") || lname.contains("android")) ? "phone" : "other"
                    rows.append(DriveRow(name: name, mount: mnt, size: t.0, used: t.1, free: t.2, pct: t.3, fs: fsByMount[mnt] ?? "—", kind: kind))
                }
            }
        }
        return rows
    }

    func padR(_ s: String, _ n: Int) -> String {
        if s.count >= n { return s }
        return String(repeating: " ", count: n - s.count) + s
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
            if let s = String(data: data, encoding: .utf8) { self?.appendLog(s) }
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
        while t.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if t.isRunning { t.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func which(_ name: String) -> String? {
        let cands = [
            "/opt/homebrew/bin/" + name,
            "/usr/local/bin/" + name,
            "/usr/bin/" + name,
            "/bin/" + name,
        ]
        for c in cands where FileManager.default.isExecutableFile(atPath: c) { return c }
        let out = run("/usr/bin/which", [name]).trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out.contains("not found") { return nil }
        return out
    }

    static func httpCode(_ url: String) -> String {
        let out = run("/usr/bin/curl", ["-sI", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "2", url])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ideviceKey(_ key: String) -> String {
        let banned = ["imei", "meid", "find my", "fmip", "appleid", "account", "internationalmobile"]
        let lk = key.lowercased()
        if banned.contains(where: { lk.contains($0) }) { return "" }
        let bin = which("ideviceinfo") ?? "/opt/homebrew/bin/ideviceinfo"
        let raw = run(bin, ["-k", key]).trimmingCharacters(in: .whitespacesAndNewlines)
        let low = raw.lowercased()
        if low.contains("imei") || low.contains("find my") || low.contains("fmip") { return "" }
        return raw
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
