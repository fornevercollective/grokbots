import Cocoa
import Foundation

let kPreservePy = "/Volumes/qbitOS/00.dev/grokbotsGH/fc-preserve/preserve.py"
let kDefaultVault = "/Volumes/MacBookPro - Data/FC-Preserve"
let kImagesDir = "/Volumes/MacBookPro - Data/FC-Preserve/images"
let kImageCatalog = kImagesDir + "/catalog.json"
let kEtcherApp = "/Applications/balenaEtcher.app"
let kLMStudioApp = "/Applications/LM Studio.app"
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

struct PickerItem {
    var id: String
    var symbol: String
    var caption: String
    var kind: String
    var subtitle: String
}

func householdPicker() -> [PickerItem] {
    return [
        PickerItem(id: "baby", symbol: "iphone", caption: "Baby", kind: "phone", subtitle: "GrokBotBaby · iPhone 7 Plus USB"),
        PickerItem(id: "brick", symbol: "iphone", caption: "Brick", kind: "phone", subtitle: "daily Continuity iPhone"),
        PickerItem(id: "mini", symbol: "desktopcomputer", caption: "Mini", kind: "desktop", subtitle: "tadericsonsMini"),
        PickerItem(id: "mbp2019", symbol: "laptopcomputer", caption: "2019 MBP", kind: "laptop", subtitle: "grokpool-laptop · machines.json"),
        PickerItem(id: "internal", symbol: "internaldrive", caption: "Internal", kind: "storage", subtitle: "/"),
        PickerItem(id: "mbpvol", symbol: "externaldrive", caption: "MBP vol", kind: "storage", subtitle: "/Volumes/MacBookPro"),
        PickerItem(id: "vault", symbol: "externaldrive", caption: "Vault", kind: "storage", subtitle: "/Volumes/MacBookPro - Data"),
        PickerItem(id: "qbitos", symbol: "externaldrive", caption: "qbitOS", kind: "storage", subtitle: "/Volumes/qbitOS"),
        PickerItem(id: "usbphone", symbol: "externaldrive", caption: "USB phone", kind: "storage", subtitle: "iPhone USB · no fs mount when hotspot"),
        PickerItem(id: "kinect", symbol: "camera.fill", caption: "Kinect", kind: "camera", subtitle: "leftover Xbox Kinect"),
        PickerItem(id: "nestcam", symbol: "camera.fill", caption: "Nest cam", kind: "camera", subtitle: "old Nest · Google A0005"),
        PickerItem(id: "nest1", symbol: "hifispeaker.fill", caption: "Nest 1", kind: "iot", subtitle: "Nest pod"),
        PickerItem(id: "nest2", symbol: "hifispeaker.fill", caption: "Nest 2", kind: "iot", subtitle: "Nest pod"),
        PickerItem(id: "yale1", symbol: "lock.fill", caption: "Yale 1", kind: "iot", subtitle: "Yale lock"),
        PickerItem(id: "yale2", symbol: "lock.fill", caption: "Yale 2", kind: "iot", subtitle: "Yale lock"),
        PickerItem(id: "tv", symbol: "tv", caption: "TV", kind: "iot", subtitle: "house TV"),
        PickerItem(id: "console", symbol: "gamecontroller", caption: "Console", kind: "iot", subtitle: "game console · LAN OUI only"),
        PickerItem(id: "wifi", symbol: "wifi", caption: "Wi-Fi", kind: "radio", subtitle: "en1 · Chariot"),
        PickerItem(id: "ble", symbol: "wave.3.right", caption: "BLE", kind: "radio", subtitle: "Brick Continuity path"),
        PickerItem(id: "nfc", symbol: "sensor.tag.radiowaves.forward", caption: "NFC", kind: "radio", subtitle: "Wallet / Continuity route only"),
        PickerItem(id: "usbhub", symbol: "cable.connector", caption: "USB hub", kind: "radio", subtitle: "iPhone@02116000 tree"),
        PickerItem(id: "qm2", symbol: "wifi.router", caption: "Qm-2", kind: "radio", subtitle: "AirPort Express · en8"),
        PickerItem(id: "bridge", symbol: "network", caption: "Bridge", kind: "radio", subtitle: "origin_bridge :8798"),
        PickerItem(id: "iso", symbol: "opticaldisc", caption: "ISO", kind: "image", subtitle: "ISO / USB tools"),
        PickerItem(id: "osimg", symbol: "server.rack", caption: "OS img", kind: "image", subtitle: "golden / customize / deploy notes"),
        PickerItem(id: "models", symbol: "cube", caption: "Models", kind: "model", subtitle: "Hugging Face / LM Studio cache"),
        PickerItem(id: "andslot", symbol: "ellipsis.circle", caption: "and…", kind: "slot", subtitle: "reserved next lane"),
    ]
}

final class LogoTile: NSView {
    let item: PickerItem
    var on: Bool = false { didSet { applyChrome() } }
    var icon: NSImageView!
    var captionLab: NSTextField!
    var click: (() -> Void)?

    init(item: PickerItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1.0
        translatesAutoresizingMaskIntoConstraints = false
        icon = symbolView(item.symbol, size: 15)
        captionLab = lab(item.caption, size: 8, weight: .medium, color: Theme.dim, wrap: true)
        captionLab.alignment = .center
        addSubview(icon)
        addSubview(captionLab)
        toolTip = item.subtitle
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 54),
            heightAnchor.constraint(equalToConstant: 50),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            captionLab.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            captionLab.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            captionLab.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
        ])
        applyChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func applyChrome() {
        layer?.backgroundColor = (on ? Theme.accent.withAlphaComponent(0.20) : Theme.inset).cgColor
        layer?.borderColor = (on ? Theme.accent.cgColor : Theme.stepOff.cgColor)
        icon.contentTintColor = on ? Theme.accent : Theme.mute
        captionLab.textColor = on ? Theme.text : Theme.dim
    }

    override func mouseDown(with event: NSEvent) {
        click?()
    }
}



final class DeviceCell: NSView {
    let item: PickerItem
    let tile: LogoTile
    let bar: StackBarView
    let cap: NSTextField
    var on: Bool {
        get { tile.on }
        set { tile.on = newValue }
    }
    var click: (() -> Void)? {
        get { tile.click }
        set { tile.click = newValue }
    }

    init(item: PickerItem) {
        self.item = item
        self.tile = LogoTile(item: item)
        self.bar = StackBarView(frame: .zero)
        self.cap = mono("0 / unknown", size: 8, color: Theme.mute)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.unknown = true
        cap.alignment = .center
        cap.lineBreakMode = .byTruncatingTail
        addSubview(tile)
        addSubview(bar)
        addSubview(cap)
        toolTip = item.subtitle
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 54),
            heightAnchor.constraint(equalToConstant: 74),
            tile.topAnchor.constraint(equalTo: topAnchor),
            tile.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.topAnchor.constraint(equalTo: tile.bottomAnchor, constant: 3),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            bar.heightAnchor.constraint(equalToConstant: 6),
            cap.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 1),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            cap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            cap.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func applyStats(used: Int64, free: Int64, known: Bool, note: String) {
        bar.unknown = !known
        bar.used = Double(max(0, used))
        bar.free = Double(max(0, free))
        bar.needsDisplay = true
        if known {
            cap.stringValue = "\(fmtBytes(used)) / \(fmtBytes(free))"
            cap.textColor = Theme.dim
        } else {
            cap.stringValue = "0 / unknown"
            cap.textColor = Theme.mute
        }
        toolTip = item.subtitle + " · " + note
        tile.toolTip = toolTip
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
    var logoTiles: [LogoTile] = []
    var deviceCells: [DeviceCell] = []
    var idBody: NSTextField!
    var thumbNote: NSTextField!
    var thumbSlots: [NSImageView] = []
    var thumbCaps: [NSTextField] = []
    var selectedIDs: Set<String> = ["baby"]
    var lastPhoneUsed: Int64 = 0
    var lastPhoneFree: Int64 = 0
    var lastPhoneKnown = false
    var lastMBPNote = "machines.json not read yet"
    var lastNestNote = "Nest cam not read yet"
    var lastKinectNote = "Kinect not read yet"
    var lastConsoleNote = "console not read yet"
    var lastWifiNote = "wifi not read yet"
    var lastUSBHubNote = "usb hub not read yet"
    var lastQm2Note = "Qm-2 not read yet"
    var lastBridgeNote = "bridge not read yet"
    var isoImagePath = ""
    var isoTargetNode = ""
    var isoTargetOK = false
    var isoTargetReason = "no removable USB picked"
    var cachedISOs: [(String, Int64, String)] = []
    var cachedModels: [(String, Int64, String)] = []
    var hfCacheBytes: Int64 = 0
    var hfCliPath = ""
    var lmsPath = ""
    var etcherPresent = false
    var isoList: NSTextView!
    var isoTargetList: NSTextView!
    var isoStatus: NSTextField!
    var isoImageField: NSTextField!
    var isoTargetField: NSTextField!
    var etcherBtn: NSButton!
    var isoFlashBtn: NSButton!
    var osCreate: NSTextField!
    var osCustomize: NSTextField!
    var osDeploy: NSTextField!
    var osCatalogView: NSTextView!
    var hfList: NSTextView!
    var hfStatus: NSTextField!
    var andSlotNote: NSTextField!
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
        let rect = NSRect(x: 0, y: 0, width: 1560, height: 940)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FC-Preserve"
        window.minSize = NSSize(width: 1280, height: 800)
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

        let strip = makeDeviceStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(strip)

        let header = lab("FC-Preserve", size: 22, weight: .semibold, color: Theme.text)
        let sub = lab("desk  ·  backup  ·  extract  ·  catalog  ·  SHA-256  ·  gate", size: 12, weight: .regular, color: Theme.dim)
        root.addSubview(header)
        root.addSubview(sub)

        let left = makeThumbsPane()
        left.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(left)

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
                pane.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                pane.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                pane.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                pane.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
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
            strip.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            strip.heightAnchor.constraint(equalToConstant: 108),
            header.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            sub.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            sub.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            left.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 12),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            left.widthAnchor.constraint(equalToConstant: 420),
            left.bottomAnchor.constraint(equalTo: primaryBtn.topAnchor, constant: -14),
            stepper.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 12),
            stepper.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 12),
            stepper.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stepper.heightAnchor.constraint(equalToConstant: 36),
            card.topAnchor.constraint(equalTo: stepper.bottomAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            card.heightAnchor.constraint(equalToConstant: 210),
            desk.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
            desk.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 12),
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
        refreshLaneInventory()
        refreshHFModels()
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
            let size = NSSize(width: min(1560, vis.width - 24), height: min(940, vis.height - 24))
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

    private func makeDeviceStrip() -> NSView {
        let wrap = NSView()
        wrap.wantsLayer = true
        wrap.layer?.backgroundColor = Theme.card.cgColor
        wrap.layer?.cornerRadius = 10
        wrap.layer?.borderWidth = 1.0
        wrap.layer?.borderColor = Theme.accent.withAlphaComponent(0.55).cgColor

        let tag = lab("SELECT DEVICE", size: 10, weight: .semibold, color: Theme.accent)
        wrap.addSubview(tag)
        let how = lab("one row · click any/all · orange selected · gray idle · bar under every logo is that device", size: 10, weight: .regular, color: Theme.mute)
        wrap.addSubview(how)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(scroll)

        let items = householdPicker()
        deviceCells = items.map { DeviceCell(item: $0) }
        logoTiles = deviceCells.map { $0.tile }
        for cell in deviceCells {
            cell.on = selectedIDs.contains(cell.item.id)
            cell.click = { [weak self, id = cell.item.id] in
                self?.toggleLogo(id)
            }
        }
        let row = NSStackView(views: deviceCells)
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(row)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            tag.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 6),
            tag.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 10),
            how.centerYAnchor.constraint(equalTo: tag.centerYAnchor),
            how.leadingAnchor.constraint(equalTo: tag.trailingAnchor, constant: 10),
            how.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: tag.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: doc.topAnchor),
            row.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            row.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            doc.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
        ])
        return wrap
    }

    private func makeThumbsPane() -> NSView {
        let wrap = NSView()
        wrap.wantsLayer = true
        wrap.layer?.backgroundColor = Theme.card.cgColor
        wrap.layer?.cornerRadius = 12

        let h = sectionTitle("THUMBNAILS + DATA", symbol: "photo.on.rectangle")
        wrap.addSubview(h)
        idBody = lab("GrokBotBaby · identity below. IMEI / Find My never shown.", size: 11, weight: .regular, color: Theme.dim, wrap: true)
        wrap.addSubview(idBody)
        usbBadge = lab("USB: probing…", size: 12, weight: .semibold, color: Theme.warn, wrap: true)
        wrap.addSubview(usbBadge)
        usbDetail = mono("", size: 10.5, color: Theme.dim, wrap: true)
        wrap.addSubview(usbDetail)

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(grid)
        thumbSlots = []
        thumbCaps = []
        var rowViews: [NSView] = []
        for i in 0..<6 {
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = Theme.inset.cgColor
            box.layer?.cornerRadius = 6
            box.layer?.borderWidth = 1
            box.layer?.borderColor = Theme.stepOff.cgColor
            box.translatesAutoresizingMaskIntoConstraints = false
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.imageAlignment = .alignCenter
            let cap = lab("empty", size: 9, weight: .regular, color: Theme.mute)
            cap.alignment = .center
            box.addSubview(iv)
            box.addSubview(cap)
            NSLayoutConstraint.activate([
                box.heightAnchor.constraint(equalToConstant: 78),
                iv.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
                iv.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
                iv.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
                iv.bottomAnchor.constraint(equalTo: cap.topAnchor, constant: -2),
                cap.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
                cap.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -2),
                cap.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3),
            ])
            thumbSlots.append(iv)
            thumbCaps.append(cap)
            rowViews.append(box)
            if rowViews.count == 3 || i == 5 {
                let r = NSStackView(views: rowViews)
                r.orientation = .horizontal
                r.distribution = .fillEqually
                r.spacing = 6
                r.translatesAutoresizingMaskIntoConstraints = false
                grid.addArrangedSubview(r)
                rowViews = []
            }
        }

        thumbNote = lab("no vault media · no AFC pull · mux empty — empty slots are honest, not placeholders of real photos.", size: 10.5, weight: .regular, color: Theme.warn, wrap: true)
        wrap.addSubview(thumbNote)

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
        let partsA = NSStackView(views: [c1, c2])
        partsA.orientation = .horizontal
        partsA.distribution = .fillEqually
        partsA.spacing = 6
        partsA.translatesAutoresizingMaskIntoConstraints = false
        let partsB = NSStackView(views: [c3, c4])
        partsB.orientation = .horizontal
        partsB.distribution = .fillEqually
        partsB.spacing = 6
        partsB.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(partsA)
        wrap.addSubview(partsB)

        deviceHint = lab("GrokBotBaby selected — vault-first backup. Flash stays locked until linux-gate.json ready.", size: 11, weight: .regular, color: Theme.dim, wrap: true)
        wrap.addSubview(deviceHint)

        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12),
            h.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            h.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            idBody.topAnchor.constraint(equalTo: h.bottomAnchor, constant: 8),
            idBody.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            idBody.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            usbBadge.topAnchor.constraint(equalTo: idBody.bottomAnchor, constant: 8),
            usbBadge.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            usbBadge.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            usbDetail.topAnchor.constraint(equalTo: usbBadge.bottomAnchor, constant: 4),
            usbDetail.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            usbDetail.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: usbDetail.bottomAnchor, constant: 10),
            grid.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            thumbNote.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
            thumbNote.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            thumbNote.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            partsA.topAnchor.constraint(equalTo: thumbNote.bottomAnchor, constant: 10),
            partsA.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            partsA.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            partsB.topAnchor.constraint(equalTo: partsA.bottomAnchor, constant: 6),
            partsB.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            partsB.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            deviceHint.topAnchor.constraint(equalTo: partsB.bottomAnchor, constant: 10),
            deviceHint.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            deviceHint.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            deviceHint.bottomAnchor.constraint(lessThanOrEqualTo: wrap.bottomAnchor, constant: -12),
        ])
        return wrap
    }

    private func makeDevicePane() -> NSView {
        let v = NSView()
        let title = lab("BACKUP 3-STEP", size: 15, weight: .semibold, color: Theme.text)
        v.addSubview(title)
        let how = lab("Device pick is the top row. This card is vault + verify only. Flash stays locked for phone / Internal / vault.", size: 11, weight: .regular, color: Theme.dim, wrap: true)
        v.addSubview(how)
        let note = lab("Step 1 of 3 — logos already live up top. Continue to pick the vault dest.", size: 12, weight: .regular, color: Theme.dim, wrap: true)
        v.addSubview(note)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: v.topAnchor),
            title.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            how.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            how.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            how.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            note.topAnchor.constraint(equalTo: how.bottomAnchor, constant: 10),
            note.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: v.trailingAnchor),
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

        let hISO = sectionTitle("ISO / USB TOOLS", symbol: "opticaldisc")
        doc.addSubview(hISO)
        let isoHow = lab("Etcher-shaped, local routes only. SELECT IMAGE → SELECT TARGET → FLASH + verify. Never the iPhone, never Internal APFS, never the Data vault, never qbitOS. Phone linux-gate still locks phone flash.", size: 11, weight: .regular, color: Theme.dim, wrap: true)
        isoHow.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(isoHow)
        isoImageField = NSTextField(string: "")
        isoImageField.placeholderString = kImagesDir + "/<file.iso>"
        isoImageField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        isoImageField.translatesAutoresizingMaskIntoConstraints = false
        isoImageField.isEditable = true
        isoImageField.isBezeled = true
        isoImageField.bezelStyle = .roundedBezel
        isoImageField.target = self
        isoImageField.action = #selector(isoImageTyped)
        doc.addSubview(isoImageField)
        let isoBrowse = button("Browse image…", filled: false, action: #selector(browseISO))
        isoBrowse.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(isoBrowse)
        let (isoScroll, isoTV) = makeTextBox(88)
        isoList = isoTV
        isoList.string = "image library probing…"
        doc.addSubview(isoScroll)
        isoTargetField = NSTextField(string: "")
        isoTargetField.placeholderString = "removable USB node or .img dest — not vault / Internal / iPhone"
        isoTargetField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        isoTargetField.translatesAutoresizingMaskIntoConstraints = false
        isoTargetField.isEditable = true
        isoTargetField.isBezeled = true
        isoTargetField.bezelStyle = .roundedBezel
        isoTargetField.target = self
        isoTargetField.action = #selector(isoTargetTyped)
        doc.addSubview(isoTargetField)
        let tgtBrowse = button("Browse dest…", filled: false, action: #selector(browseISODest))
        tgtBrowse.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(tgtBrowse)
        let (tgtScroll, tgtTV) = makeTextBox(72)
        isoTargetList = tgtTV
        isoTargetList.string = "flash targets probing…"
        doc.addSubview(tgtScroll)
        isoStatus = lab("FLASH locked — no removable USB picked.", size: 11, weight: .medium, color: Theme.warn, wrap: true)
        doc.addSubview(isoStatus)
        etcherBtn = button("Open balenaEtcher", filled: false, action: #selector(openEtcher))
        etcherBtn.translatesAutoresizingMaskIntoConstraints = false
        isoFlashBtn = button("FLASH + verify (local)", filled: true, action: #selector(flashISO))
        isoFlashBtn.translatesAutoresizingMaskIntoConstraints = false
        isoFlashBtn.isEnabled = false
        let isoBtns = NSStackView(views: [etcherBtn, isoFlashBtn])
        isoBtns.orientation = .horizontal
        isoBtns.spacing = 8
        isoBtns.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(isoBtns)

        let hOS = sectionTitle("OS IMAGE MANAGEMENT", symbol: "server.rack")
        doc.addSubview(hOS)
        let osHow = lab("Create / Customize / Deploy cards. Notes + ISO/USB route only — not zero-touch wipe. Not ManageEngine. Hardware-independent note is text only.", size: 11, weight: .regular, color: Theme.dim, wrap: true)
        osHow.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(osHow)
        var oc: NSTextField!
        var oz: NSTextField!
        var od: NSTextField!
        let os1 = partCard(symbol: "plus.square", title: "CREATE", body: &oc)
        let os2 = partCard(symbol: "slider.horizontal.3", title: "CUSTOMIZE", body: &oz)
        let os3 = partCard(symbol: "shippingbox", title: "DEPLOY", body: &od)
        osCreate = oc
        osCustomize = oz
        osDeploy = od
        let osCards = NSStackView(views: [os1, os2, os3])
        osCards.orientation = .horizontal
        osCards.distribution = .fillEqually
        osCards.spacing = 8
        osCards.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(osCards)
        let (osScroll, osTV) = makeTextBox(96)
        osCatalogView = osTV
        osCatalogView.string = "catalog.json probing…"
        doc.addSubview(osScroll)

        let hHF = sectionTitle("MODELS", symbol: "cube")
        doc.addSubview(hHF)
        hfStatus = lab("Hugging Face cache / LM Studio — probing. Will not download.", size: 11, weight: .medium, color: Theme.dim, wrap: true)
        doc.addSubview(hfStatus)
        let (hfScroll, hfTV) = makeTextBox(120)
        hfList = hfTV
        hfList.string = "local models probing…"
        doc.addSubview(hfScroll)
        let hfCopy = button("Copy selected path", filled: false, action: #selector(copyHFPath))
        hfCopy.translatesAutoresizingMaskIntoConstraints = false
        let hfOpen = button("Open LM Studio", filled: false, action: #selector(openLMStudio))
        hfOpen.translatesAutoresizingMaskIntoConstraints = false
        let hfDir = button("Open HF cache", filled: false, action: #selector(openHFCache))
        hfDir.translatesAutoresizingMaskIntoConstraints = false
        let hfBtns = NSStackView(views: [hfCopy, hfOpen, hfDir])
        hfBtns.orientation = .horizontal
        hfBtns.spacing = 8
        hfBtns.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(hfBtns)

        let hAnd = sectionTitle("AND…", symbol: "ellipsis.circle")
        doc.addSubview(hAnd)
        andSlotNote = lab("Reserved lane. Tad ended with and — next tool sits here. Empty on purpose.", size: 11, weight: .regular, color: Theme.mute, wrap: true)
        doc.addSubview(andSlotNote)

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
            hISO.topAnchor.constraint(equalTo: flagsScroll.bottomAnchor, constant: 14),
            hISO.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoHow.topAnchor.constraint(equalTo: hISO.bottomAnchor, constant: 4),
            isoHow.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoHow.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            isoImageField.topAnchor.constraint(equalTo: isoHow.bottomAnchor, constant: 8),
            isoImageField.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoImageField.trailingAnchor.constraint(equalTo: isoBrowse.leadingAnchor, constant: -8),
            isoImageField.heightAnchor.constraint(equalToConstant: 26),
            isoBrowse.centerYAnchor.constraint(equalTo: isoImageField.centerYAnchor),
            isoBrowse.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            isoBrowse.widthAnchor.constraint(equalToConstant: 128),
            isoScroll.topAnchor.constraint(equalTo: isoImageField.bottomAnchor, constant: 6),
            isoScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            isoTargetField.topAnchor.constraint(equalTo: isoScroll.bottomAnchor, constant: 8),
            isoTargetField.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoTargetField.trailingAnchor.constraint(equalTo: tgtBrowse.leadingAnchor, constant: -8),
            isoTargetField.heightAnchor.constraint(equalToConstant: 26),
            tgtBrowse.centerYAnchor.constraint(equalTo: isoTargetField.centerYAnchor),
            tgtBrowse.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            tgtBrowse.widthAnchor.constraint(equalToConstant: 128),
            tgtScroll.topAnchor.constraint(equalTo: isoTargetField.bottomAnchor, constant: 6),
            tgtScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            tgtScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            isoStatus.topAnchor.constraint(equalTo: tgtScroll.bottomAnchor, constant: 6),
            isoStatus.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            isoStatus.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            isoBtns.topAnchor.constraint(equalTo: isoStatus.bottomAnchor, constant: 6),
            isoBtns.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            hOS.topAnchor.constraint(equalTo: isoBtns.bottomAnchor, constant: 14),
            hOS.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            osHow.topAnchor.constraint(equalTo: hOS.bottomAnchor, constant: 4),
            osHow.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            osHow.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            osCards.topAnchor.constraint(equalTo: osHow.bottomAnchor, constant: 6),
            osCards.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            osCards.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            osCards.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            osScroll.topAnchor.constraint(equalTo: osCards.bottomAnchor, constant: 6),
            osScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            osScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            hHF.topAnchor.constraint(equalTo: osScroll.bottomAnchor, constant: 14),
            hHF.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            hfStatus.topAnchor.constraint(equalTo: hHF.bottomAnchor, constant: 4),
            hfStatus.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            hfStatus.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            hfScroll.topAnchor.constraint(equalTo: hfStatus.bottomAnchor, constant: 6),
            hfScroll.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            hfScroll.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            hfBtns.topAnchor.constraint(equalTo: hfScroll.bottomAnchor, constant: 6),
            hfBtns.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            hAnd.topAnchor.constraint(equalTo: hfBtns.bottomAnchor, constant: 14),
            hAnd.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            andSlotNote.topAnchor.constraint(equalTo: hAnd.bottomAnchor, constant: 4),
            andSlotNote.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pad),
            andSlotNote.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pad),
            h4.topAnchor.constraint(equalTo: andSlotNote.bottomAnchor, constant: 14),
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

    @objc func toggleLogo(_ id: String) {
        if selectedIDs.contains(id) {
            if selectedIDs.count == 1 { return }
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        if selectedIDs.contains("baby") {
            alias = "GrokBotBaby"
        } else if selectedIDs.contains("brick") {
            alias = "Brick"
        } else {
            alias = "GrokBotBaby"
        }
        for tile in logoTiles {
            tile.on = selectedIDs.contains(tile.item.id)
        }
        refreshPickerHint()
        refreshIdentity()
        applyParts(phoneUsed: lastPhoneUsed, phoneFree: lastPhoneFree, phoneKnown: lastPhoneKnown)
        rebuildStorageBars()
        refreshThumbs()
    }

    func refreshPickerHint() {
        let names = householdPicker().filter { selectedIDs.contains($0.id) }.map { $0.caption }
        let joined = names.joined(separator: ", ")
        if selectedIDs.contains("baby") {
            deviceHint.stringValue = "Selected: \(joined). Vault-first backup is preserve.py all GrokBotBaby when mux is up. Flash stays locked."
        } else if selectedIDs.contains("brick") {
            deviceHint.stringValue = "Selected: \(joined). Brick is preserve only, never flash. Vault-first phone path stays GrokBotBaby unless Brick is the only phone."
        } else {
            deviceHint.stringValue = "Selected: \(joined). No phone in the set — backup still preserve.py all GrokBotBaby when mux is up. Not blocking on hotspot."
        }
    }

    func makeBarRow(title: String, used: Int64, free: Int64, known: Bool, note: String) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        let name = lab(title, size: 11, weight: .semibold, color: Theme.text)
        let bar = StackBarView(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.unknown = !known
        bar.used = Double(max(0, used))
        bar.free = Double(max(0, free))
        let cap: NSTextField
        if known {
            let pct = used + free > 0 ? Int((Double(used) / Double(used + free)) * 100.0) : 0
            cap = mono("used \(fmtBytes(used)) / free \(fmtBytes(free)) / \(pct)%  ·  \(note)", size: 10.5, color: Theme.dim, wrap: true)
        } else {
            cap = mono("used 0 / free 0 — unknown  ·  \(note)", size: 10.5, color: Theme.mute, wrap: true)
        }
        box.addSubview(name)
        box.addSubview(bar)
        box.addSubview(cap)
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: box.topAnchor),
            name.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            name.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            bar.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 16),
            cap.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 3),
            cap.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            cap.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            cap.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    func driveNamed(_ name: String) -> DriveRow? {
        return lastDrives.first(where: { $0.name == name || $0.mount == name })
    }

    func rebuildStorageBars() {
        if deviceCells.isEmpty { return }
        for cell in deviceCells {
            let s = statsForItem(cell.item)
            cell.applyStats(used: s.0, free: s.1, known: s.2, note: s.3)
        }
    }

    func statsForItem(_ item: PickerItem) -> (Int64, Int64, Bool, String) {
        switch item.id {
        case "internal":
            if let d = driveNamed("Internal") ?? lastDrives.first(where: { $0.mount == "/" }) {
                return (d.used, d.free, d.size > 0, "\(d.mount) · flagged tight if free < 50 Gi")
            }
            return (0, 0, false, "not mounted")
        case "mbpvol":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/MacBookPro" }) {
                return (d.used, d.free, d.size > 0, d.mount)
            }
            return (0, 0, false, "volume not mounted")
        case "vault":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/MacBookPro - Data" }) {
                return (d.used, d.free, d.size > 0, "\(d.mount) · dest \(kDefaultVault)")
            }
            return (0, 0, false, "MacBookPro - Data not mounted")
        case "qbitos":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/qbitOS" }) {
                return (d.used, d.free, d.size > 0, "lab SSD · not the vault")
            }
            return (0, 0, false, "not mounted")
        case "usbphone", "baby":
            return (lastPhoneUsed, lastPhoneFree, lastPhoneKnown, lastMux.isEmpty ? "mux empty · no fs mount" : "mux up")
        case "brick":
            return (0, 0, false, "Continuity daily · size unknown until that phone is on mux")
        case "mini":
            if let d = lastDrives.first(where: { $0.mount == "/" }) {
                return (d.used, d.free, d.size > 0, "tadericsonsMini Internal")
            }
            return (0, 0, false, "tadericsonsMini")
        case "mbp2019":
            return (0, 0, false, lastMBPNote)
        case "kinect":
            return (0, 0, false, lastKinectNote)
        case "nestcam":
            return (0, 0, false, lastNestNote)
        case "wifi":
            return (0, 0, false, lastWifiNote)
        case "ble":
            return (0, 0, false, "Brick Continuity path · no BLE session claimed")
        case "nfc":
            return (0, 0, false, "Wallet / Continuity route only · no session claimed")
        case "usbhub":
            return (0, 0, false, lastUSBHubNote)
        case "qm2":
            return (0, 0, false, lastQm2Note)
        case "bridge":
            return (0, 0, false, lastBridgeNote)
        case "nest1", "nest2", "yale1", "yale2", "tv", "console":
            return (0, 0, false, lastIoTNote(item.id))
        case "iso":
            let used = cachedISOs.reduce(Int64(0)) { $0 + $1.1 }
            return (used, 0, !cachedISOs.isEmpty, cachedISOs.isEmpty ? "library empty — no size" : "\(cachedISOs.count) file(s) in images/")
        case "osimg":
            let present = FileManager.default.fileExists(atPath: kImageCatalog)
            return (0, 0, false, present ? "catalog.json notes only — no golden ISO" : "catalog.json not written yet")
        case "models":
            return (hfCacheBytes, 0, hfCacheBytes > 0, hfCacheBytes > 0 ? "local hub only — will not download" : "size pending / unknown")
        case "andslot":
            return (0, 0, false, "reserved next lane")
        default:
            return (0, 0, false, item.subtitle)
        }
    }

    func refreshThumbs() {
        if thumbSlots.isEmpty { return }
        let found = findMediaThumbs()
        for (i, slot) in thumbSlots.enumerated() {
            if i < found.count {
                let (path, kind) = found[i]
                if kind == "image", let img = NSImage(contentsOfFile: path) {
                    slot.image = img
                    slot.contentTintColor = nil
                    thumbCaps[i].stringValue = (path as NSString).lastPathComponent
                    thumbCaps[i].textColor = Theme.dim
                    slot.superview?.layer?.borderColor = Theme.accent.withAlphaComponent(0.45).cgColor
                } else {
                    slot.image = nil
                    if #available(macOS 11.0, *) {
                        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                        slot.image = NSImage(systemSymbolName: kind == "video" ? "film" : "photo", accessibilityDescription: kind)?.withSymbolConfiguration(cfg)
                    }
                    slot.contentTintColor = Theme.mute
                    thumbCaps[i].stringValue = (path as NSString).lastPathComponent
                    thumbCaps[i].textColor = Theme.dim
                    slot.superview?.layer?.borderColor = Theme.stepOff.cgColor
                }
            } else {
                slot.image = nil
                if #available(macOS 11.0, *) {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                    slot.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "empty")?.withSymbolConfiguration(cfg)
                }
                slot.contentTintColor = Theme.stepOff
                thumbCaps[i].stringValue = "empty"
                thumbCaps[i].textColor = Theme.mute
                slot.superview?.layer?.borderColor = Theme.stepOff.cgColor
            }
        }
        if found.isEmpty {
            var line = "no vault media · no AFC pull"
            if lastMuxEmpty { line += " · mux empty" }
            if lastHotspot { line += " · Personal Hotspot has the cable — turn hotspot off, unlock, Trust" }
            line += " — empty slots are honest, not fake photos."
            thumbNote.stringValue = line
            thumbNote.textColor = Theme.warn
        } else {
            thumbNote.stringValue = "\(found.count) file(s) on disk (vault extract / AFC / live.jpg). Not inventing frames."
            thumbNote.textColor = Theme.ok
        }
    }

    func findMediaThumbs() -> [(String, String)] {
        var out: [(String, String)] = []
        let fm = FileManager.default
        let imgExt = Set(["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"])
        let vidExt = Set(["mov", "mp4", "m4v", "avi"])
        var roots: [String] = [
            kDefaultVault + "/GrokBotBaby",
            kDefaultVault + "/Brick",
            "/tmp/live.jpg",
        ]
        if let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for n in vols {
                let low = n.lowercased()
                if low.contains("iphone") || low.contains("dcim") || low.contains("afc") {
                    roots.append("/Volumes/" + n)
                }
            }
        }
        for root in roots {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: root, isDirectory: &isDir) == false { continue }
            if !isDir.boolValue {
                let ext = (root as NSString).pathExtension.lowercased()
                if imgExt.contains(ext) { out.append((root, "image")) }
                else if vidExt.contains(ext) { out.append((root, "video")) }
                continue
            }
            guard let en = fm.enumerator(atPath: root) else { continue }
            var seen = 0
            while let rel = en.nextObject() as? String {
                let low = rel.lowercased()
                if low.contains("/backup/") && !low.contains("/media/") { continue }
                let ext = (rel as NSString).pathExtension.lowercased()
                if imgExt.contains(ext) {
                    out.append((root + "/" + rel, "image"))
                    seen += 1
                } else if vidExt.contains(ext) {
                    out.append((root + "/" + rel, "video"))
                    seen += 1
                }
                if seen >= 12 { break }
            }
        }
        return Array(out.prefix(6))
    }

    func refreshIdentity() {
        if idBody == nil { return }
        let names = householdPicker().filter { selectedIDs.contains($0.id) }.map { $0.caption }
        let joined = names.joined(separator: ", ")
        var lines = "Selected: \(joined)"
        if selectedIDs.contains("baby") {
            lines += "\nGrokBotBaby · iPhone 7 Plus · iPhone9,4 D111AP A10 · iOS 15.1"
            lines += "\nUDID \(kBabyUDID)"
            lines += "\nSerial \(kBabySerial)"
            lines += "\nIMEI / Find My never shown."
        } else if selectedIDs.contains("brick") {
            lines += "\nBrick · daily Continuity iPhone"
            lines += "\nUDID unknown until that phone is on mux."
            lines += "\nIMEI / Find My never shown."
        } else {
            lines += "\nNo phone in the set. Public GrokBotBaby UDID still listed for the vault path:"
            lines += "\nUDID \(kBabyUDID)  ·  Serial \(kBabySerial)"
            lines += "\nIMEI / Find My never shown."
        }
        idBody.stringValue = lines
    }

    func barForItem(_ item: PickerItem) -> NSView {
        switch item.id {
        case "internal":
            if let d = driveNamed("Internal") ?? lastDrives.first(where: { $0.mount == "/" }) {
                return makeBarRow(title: "Internal", used: d.used, free: d.free, known: d.size > 0, note: "\(d.mount) · flagged tight if free < 50 Gi")
            }
            return makeBarRow(title: "Internal", used: 0, free: 0, known: false, note: "not mounted")
        case "mbpvol":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/MacBookPro" }) {
                return makeBarRow(title: "MacBookPro", used: d.used, free: d.free, known: d.size > 0, note: d.mount)
            }
            return makeBarRow(title: "MacBookPro", used: 0, free: 0, known: false, note: "volume not mounted")
        case "vault":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/MacBookPro - Data" }) {
                return makeBarRow(title: "Vault volume", used: d.used, free: d.free, known: d.size > 0, note: "\(d.mount) · dest \(kDefaultVault)")
            }
            return makeBarRow(title: "Vault volume", used: 0, free: 0, known: false, note: "MacBookPro - Data not mounted")
        case "qbitos":
            if let d = lastDrives.first(where: { $0.mount == "/Volumes/qbitOS" }) {
                return makeBarRow(title: "qbitOS", used: d.used, free: d.free, known: d.size > 0, note: "lab SSD · not the vault")
            }
            return makeBarRow(title: "qbitOS", used: 0, free: 0, known: false, note: "not mounted")
        case "usbphone", "baby":
            let known = lastPhoneKnown
            return makeBarRow(title: item.id == "baby" ? "GrokBotBaby" : "USB iPhone", used: lastPhoneUsed, free: lastPhoneFree, known: known, note: lastMux.isEmpty ? "mux empty · no fs mount" : "mux up")
        case "brick":
            return makeBarRow(title: "Brick", used: 0, free: 0, known: false, note: "Continuity daily · size unknown until that phone is on mux")
        case "mini":
            if let d = lastDrives.first(where: { $0.mount == "/" }) {
                return makeBarRow(title: "Mini", used: d.used, free: d.free, known: d.size > 0, note: "tadericsonsMini Internal")
            }
            return makeBarRow(title: "Mini", used: 0, free: 0, known: false, note: "tadericsonsMini")
        case "mbp2019":
            return makeBarRow(title: "2019 MBP", used: 0, free: 0, known: false, note: lastMBPNote)
        case "kinect":
            return makeBarRow(title: "Kinect", used: 0, free: 0, known: false, note: lastKinectNote)
        case "nestcam":
            return makeBarRow(title: "Nest cam", used: 0, free: 0, known: false, note: lastNestNote)
        case "wifi":
            return makeBarRow(title: "Wi-Fi en1", used: 0, free: 0, known: false, note: lastWifiNote)
        case "ble":
            return makeBarRow(title: "BLE", used: 0, free: 0, known: false, note: "Brick Continuity path · no BLE session claimed")
        case "nfc":
            return makeBarRow(title: "NFC", used: 0, free: 0, known: false, note: "Wallet / Continuity route only · no session claimed")
        case "usbhub":
            return makeBarRow(title: "USB hub", used: 0, free: 0, known: false, note: lastUSBHubNote)
        case "qm2":
            return makeBarRow(title: "Qm-2", used: 0, free: 0, known: false, note: lastQm2Note)
        case "bridge":
            return makeBarRow(title: "origin_bridge", used: 0, free: 0, known: false, note: lastBridgeNote)
        case "nest1", "nest2", "yale1", "yale2", "tv", "console":
            return makeBarRow(title: item.caption, used: 0, free: 0, known: false, note: lastIoTNote(item.id))
        case "iso":
            let used = cachedISOs.reduce(Int64(0)) { $0 + $1.1 }
            return makeBarRow(title: "ISO library", used: used, free: 0, known: !cachedISOs.isEmpty, note: cachedISOs.isEmpty ? "library empty — no size" : "\(cachedISOs.count) file(s) in images/")
        case "osimg":
            let present = FileManager.default.fileExists(atPath: kImageCatalog)
            return makeBarRow(title: "OS catalog", used: 0, free: 0, known: false, note: present ? "catalog.json notes only — no golden ISO" : "catalog.json not written yet")
        case "models":
            return makeBarRow(title: "HF cache", used: hfCacheBytes, free: 0, known: hfCacheBytes > 0, note: hfCacheBytes > 0 ? "local hub only — will not download" : "size pending / unknown")
        case "andslot":
            return makeBarRow(title: "and…", used: 0, free: 0, known: false, note: "reserved next lane")
        default:
            return makeBarRow(title: item.caption, used: 0, free: 0, known: false, note: item.subtitle)
        }
    }

    func lastIoTNote(_ id: String) -> String {
        if id == "console" { return lastConsoleNote }
        return "household inventory · not labeled in LATEST-lan-devices.json (anonymous device-N, 2026-08-15) · not starting a scan"
    }

    @objc func isoImageTyped() {
        isoImagePath = isoImageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshISOFlashState()
    }

    @objc func isoTargetTyped() {
        isoTargetNode = isoTargetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        classifyISOTarget()
        refreshISOFlashState()
    }

    @objc func browseISO() {
        ensureImagesDir()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: kImagesDir)
        panel.allowedFileTypes = ["iso", "img", "dmg", "zip"]
        panel.prompt = "Select image"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            self.isoImagePath = url.path
            self.isoImageField.stringValue = url.path
            self.refreshISOFlashState()
        }
    }

    @objc func browseISODest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: kImagesDir)
        panel.prompt = "Select dest"
        panel.message = "Removable USB or a disk-image file. Internal / vault / qbitOS / iPhone are refused."
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            self.isoTargetNode = url.path
            self.isoTargetField.stringValue = url.path
            self.classifyISOTarget()
            self.refreshISOFlashState()
        }
    }

    @objc func openEtcher() {
        if FileManager.default.fileExists(atPath: kEtcherApp) {
            NSWorkspace.shared.open(URL(fileURLWithPath: kEtcherApp))
        } else if isoStatus != nil {
            isoStatus.stringValue = "balenaEtcher.app not in /Applications — route only, not installed."
            isoStatus.textColor = Theme.warn
        }
    }

    @objc func openLMStudio() {
        if FileManager.default.fileExists(atPath: kLMStudioApp) {
            NSWorkspace.shared.open(URL(fileURLWithPath: kLMStudioApp))
        }
    }

    @objc func openHFCache() {
        let p = NSHomeDirectory() + "/.cache/huggingface"
        if FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        }
    }

    @objc func copyHFPath() {
        if let first = cachedModels.first {
            copyString(first.2)
            if hfStatus != nil { hfStatus.stringValue = "copied " + first.2 }
        } else {
            copyString(NSHomeDirectory() + "/.cache/huggingface/hub")
        }
    }

    @objc func flashISO() {
        classifyISOTarget()
        refreshISOFlashState()
        if !isoTargetOK {
            isoStatus.stringValue = "FLASH refused — " + isoTargetReason
            isoStatus.textColor = Theme.bad
            return
        }
        let img = isoImagePath
        if !isSafeImage(img) {
            isoStatus.stringValue = "FLASH refused — pick a .iso/.img/.dmg/.zip from the image library or Browse."
            isoStatus.textColor = Theme.bad
            return
        }
        let alert = NSAlert()
        alert.messageText = "Write image to dest?"
        alert.informativeText = "IMAGE: \(img)\nDEST: \(isoTargetNode)\n\nLocal ISO/USB only. Will not flash GrokBotBaby or Brick. Will not touch Internal / vault / qbitOS.\ndd is last resort and needs this confirm. Prefer Etcher for USB sticks."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Etcher instead")
        alert.addButton(withTitle: "Confirm local write")
        alert.addButton(withTitle: "Cancel")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            openEtcher()
            return
        }
        if resp != .alertSecondButtonReturn { return }
        runLocalImageWrite(image: img, dest: isoTargetNode)
    }

    func runLocalImageWrite(image: String, dest: String) {
        classifyISOTarget()
        if !isoTargetOK {
            isoStatus.stringValue = "FLASH aborted — dest changed / refused: " + isoTargetReason
            isoStatus.textColor = Theme.bad
            return
        }
        if dest.hasPrefix("/dev/") {
            isoStatus.stringValue = "last-resort dd not launched as root. Copied dd if=… of=… bs=4m. Open Etcher for a privileged USB write."
            isoStatus.textColor = Theme.warn
            copyString("dd if=\(image) of=\(dest) bs=4m")
            return
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dest, isDirectory: &isDir)
        let destIsFile = dest.hasSuffix(".img") || dest.hasSuffix(".dmg") || dest.hasSuffix(".iso") || !exists || !isDir.boolValue
        if destIsFile && dest.hasPrefix(kImagesDir) {
            let out = Self.run("/usr/bin/hdiutil", ["convert", image, "-format", "UDRW", "-o", dest])
            isoStatus.stringValue = "hdiutil convert → \(dest)\n" + String(out.prefix(400))
            isoStatus.textColor = Theme.ok
            return
        }
        isoStatus.stringValue = "FLASH refused — dest is not a removable disk node or images/ disk-image file."
        isoStatus.textColor = Theme.bad
    }

    func isSafeImage(_ path: String) -> Bool {
        let p = (path as NSString).expandingTildeInPath
        if p.isEmpty { return false }
        if !FileManager.default.fileExists(atPath: p) { return false }
        let low = p.lowercased()
        return low.hasSuffix(".iso") || low.hasSuffix(".img") || low.hasSuffix(".dmg") || low.hasSuffix(".zip")
    }

    func ensureImagesDir() {
        try? FileManager.default.createDirectory(atPath: kImagesDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: kImageCatalog) {
            try? defaultOSCatalog().write(toFile: kImageCatalog, atomically: true, encoding: .utf8)
        }
    }

    func defaultOSCatalog() -> String {
        return """
        {
          "schema": "fc-preserve-os-catalog-v1",
          "vault": "\(kImagesDir)",
          "note": "Inspired OS Deployer UX. Notes + ISO/USB routes only. Not zero-touch wipe. Not ManageEngine.",
          "images": [],
          "goldens": [
            {"id": "mini", "host": "tadericsonsMini", "kind": "apple-silicon-desktop", "iso": null, "drivers": "Apple Silicon. USB DockCaseAx on en8.", "post": "preserve.py, origin_bridge :8798, do not start Elffin.", "deploy": "notes only — will not wipe Mini"},
            {"id": "mbp2019", "host": "grokpool-laptop", "kind": "intel-mbp-2019", "iso": null, "drivers": "unknown until SSH .89 — not started", "post": "SSH HostName .89 not the stale remap.", "deploy": "notes only — will not wipe 2019 MBP"},
            {"id": "linux-test", "host": "GrokBotBaby", "kind": "iphone-linux-future", "iso": null, "drivers": "A10 checkm8 / linux-gate.json", "post": "flash locked until gate.ready", "deploy": "phone flash locked"}
          ],
          "hw_independent": "Hardware-independent image is a text note only. No sysprep/generalized image is claimed."
        }
        """
    }

    func refreshLaneInventory() {
        ensureImagesDir()
        cachedISOs = listImages()
        etcherPresent = FileManager.default.fileExists(atPath: kEtcherApp)
        hfCliPath = Self.which("hf") ?? Self.which("huggingface-cli") ?? ""
        lmsPath = Self.which("lms") ?? ""
        if isoList != nil { applyISOLists() }
        if osCatalogView != nil { applyOSCatalog() }
        refreshISOFlashState()
    }

    func listImages() -> [(String, Int64, String)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: kImagesDir) else { return [] }
        var out: [(String, Int64, String)] = []
        for n in names.sorted() {
            let low = n.lowercased()
            if !(low.hasSuffix(".iso") || low.hasSuffix(".img") || low.hasSuffix(".dmg") || low.hasSuffix(".zip")) { continue }
            let path = kImagesDir + "/" + n
            let sz = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            out.append((n, sz, path))
        }
        return out
    }

    func applyISOLists() {
        if cachedISOs.isEmpty {
            isoList.string = "library empty — " + kImagesDir + "\nDrop .iso / .img / .dmg / .zip here. No OS installer is in the vault yet. Not scanning Downloads."
        } else {
            var s = "LIBRARY  " + kImagesDir + "\n"
            for (n, sz, path) in cachedISOs {
                s += "\(n)  \(fmtBytes(sz))  \(path)\n"
            }
            isoList.string = s
        }
        var t = "FLASH TARGETS (refused unless removable + user-picked)\n"
        let tgts = listFlashTargets()
        if tgts.isEmpty {
            t += "no removable USB right now. qbitOS + MacBookPro Data are USB-attached but Fixed / refused.\n"
        } else {
            for line in tgts { t += line + "\n" }
        }
        t += "Etcher: " + (etcherPresent ? kEtcherApp : "not installed") + " · hdiutil present · dd last resort + confirm"
        isoTargetList.string = t
    }

    func listFlashTargets() -> [String] {
        let list = Self.run("/usr/sbin/diskutil", ["list", "external"])
        var lines: [String] = []
        for row in list.split(separator: "\n") {
            let s = String(row)
            if s.contains("/dev/disk") { lines.append(s) }
        }
        return lines
    }
    func classifyISOTarget() {
        let raw = isoTargetNode.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = (raw as NSString).expandingTildeInPath
        isoTargetOK = false
        isoTargetReason = "no dest"
        if dest.isEmpty {
            isoTargetReason = "no dest picked"
            return
        }
        let low = dest.lowercased()
        if low.contains("iphone") || low.contains("grokbotbaby") || low.contains("brick") {
            isoTargetReason = "refused — phone is never an ISO dest"
            return
        }
        if dest.hasPrefix(kImagesDir) && (low.hasSuffix(".img") || low.hasSuffix(".dmg") || low.hasSuffix(".iso")) {
            isoTargetOK = true
            isoTargetReason = "disk-image dest under images/"
            return
        }
        if dest == "/" || dest.hasPrefix("/System") {
            isoTargetReason = "refused — Internal APFS system"
            return
        }
        if dest.hasPrefix("/Users/") {
            isoTargetReason = "refused — user home is not a USB dest"
            return
        }
        if dest == "/Volumes/MacBookPro - Data" || (dest.hasPrefix("/Volumes/MacBookPro - Data/") && !dest.hasPrefix(kImagesDir)) {
            isoTargetReason = "refused — Data vault is not a USB dest"
            return
        }
        if dest == "/Volumes/qbitOS" || dest.hasPrefix("/Volumes/qbitOS/") {
            isoTargetReason = "refused — qbitOS lab SSD is not a USB dest"
            return
        }
        if dest == "/Volumes/MacBookPro" || dest.hasPrefix("/Volumes/MacBookPro/") {
            isoTargetReason = "refused — MacBookPro volume is not a USB dest"
            return
        }
        if dest.hasPrefix("/dev/disk") {
            let info = Self.run("/usr/sbin/diskutil", ["info", dest])
            if info.contains("APPLE SSD") || info.contains("Device Location:           Internal") {
                isoTargetReason = "refused — Internal APFS system"
                return
            }
            if info.contains("qbitOS") || info.contains("MacBookPro") || info.contains("Macintosh HD") {
                isoTargetReason = "refused — vault / lab / system disk"
                return
            }
            if info.contains("Removable Media:           Yes") {
                isoTargetOK = true
                isoTargetReason = "removable USB node " + dest
                return
            }
            isoTargetReason = "refused — " + dest + " is not Removable Media (Fixed USB SSDs stay locked)"
            return
        }
        isoTargetReason = "refused — dest is not a removable USB node or images/ disk-image file"
    }

    func refreshISOFlashState() {
        classifyISOTarget()
        let imgOK = isSafeImage(isoImagePath)
        let ready = imgOK && isoTargetOK
        if isoFlashBtn != nil { isoFlashBtn.isEnabled = ready }
        if isoStatus == nil { return }
        if ready {
            isoStatus.stringValue = "FLASH ready — image and removable dest accepted. Phone flash still locked."
            isoStatus.textColor = Theme.ok
        } else if !imgOK && isoTargetNode.isEmpty {
            isoStatus.stringValue = "FLASH locked — pick an image and a removable dest. Etcher route available. Phone linux-gate still locks phone flash."
            isoStatus.textColor = Theme.warn
        } else {
            isoStatus.stringValue = "FLASH locked — image " + (imgOK ? "ok" : "missing") + " · dest " + isoTargetReason
            isoStatus.textColor = Theme.warn
        }
        if etcherBtn != nil { etcherBtn.isEnabled = FileManager.default.fileExists(atPath: kEtcherApp) }
    }

    func applyOSCatalog() {
        ensureImagesDir()
        osCreate.stringValue = "Golden notes for Mini / 2019 MBP / future linux-test. No ISO in the library yet. Will not invent a golden."
        osCustomize.stringValue = "Driver notes only. Mini: Apple Silicon. 2019 MBP: unknown until SSH .89 (not started). Baby: linux-gate locked."
        osDeploy.stringValue = "Deploy = notes + chosen ISO/USB route. Not zero-touch wipe. Phone flash locked."
        if let txt = try? String(contentsOfFile: kImageCatalog, encoding: .utf8) {
            osCatalogView.string = txt
        } else {
            osCatalogView.string = "catalog.json missing — will write default notes on first ensure."
        }
    }

    func refreshHFModels() {
        let hub = NSHomeDirectory() + "/.cache/huggingface/hub"
        let lms = NSHomeDirectory() + "/.lmstudio/models"
        var rows: [(String, Int64, String)] = []
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: hub) {
            for n in names.sorted() where n.hasPrefix("models--") {
                let path = hub + "/" + n
                let pretty = n.replacingOccurrences(of: "models--", with: "").replacingOccurrences(of: "--", with: "/")
                rows.append((pretty, 0, path))
            }
        }
        if let names = try? fm.contentsOfDirectory(atPath: lms) {
            for n in names.sorted() {
                let path = lms + "/" + n
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    rows.append(("LM Studio/" + n, 0, path))
                }
            }
        }
        cachedModels = rows
        applyHFList()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var sized: [(String, Int64, String)] = []
            var cache: Int64 = 0
            for (n, _, path) in rows {
                let du = PreserveWindow.run("/usr/bin/du", ["-sk", path])
                let kib = du.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Int64($0) } ?? 0
                let bytes = kib * 1024
                cache += bytes
                sized.append((n, bytes, path))
            }
            DispatchQueue.main.async {
                self.cachedModels = sized
                self.hfCacheBytes = cache
                self.applyHFList()
            }
        }
    }

    func applyHFList() {
        if hfList == nil { return }
        let hubOK = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.cache/huggingface")
        let lmsDir = NSHomeDirectory() + "/.lmstudio/models"
        let lmsEmpty: Bool
        if let n = try? FileManager.default.contentsOfDirectory(atPath: lmsDir) {
            lmsEmpty = n.isEmpty
        } else { lmsEmpty = true }
        let cli = hfCliPath.isEmpty ? "hf / huggingface-cli not on PATH · route: hf download <repo>" : hfCliPath
        let lmsbin = lmsPath.isEmpty ? "lms not on PATH" : lmsPath
        let app = FileManager.default.fileExists(atPath: kLMStudioApp) ? "app present" : "app missing"
        let cacheTxt = hfCacheBytes > 0 ? fmtBytes(hfCacheBytes) : (hubOK ? "size pending" : "missing")
        hfStatus.stringValue = "HF cache " + cacheTxt + "  ·  " + cli + "  ·  LM Studio " + app + "  ·  " + lmsbin + ". Will not download. Will not start a GPU host."
        if cachedModels.isEmpty {
            hfList.string = "no local HF hub models found. LM Studio models dir " + (lmsEmpty ? "empty" : "present") + "."
            return
        }
        var s = "NAME                                      SIZE     PATH\n"
        for (n, sz, path) in cachedModels {
            let name = n.padding(toLength: 42, withPad: " ", startingAt: 0)
            let sizeTxt = sz > 0 ? fmtBytes(sz) : "unknown"
            s += "\(name) \(padR(sizeTxt, 7))  \(path)\n"
        }
        hfList.string = s
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
        rebuildStorageBars()
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
        var mbpNote: String
        var nestNote: String
        var kinectNote: String
        var consoleNote: String
        var wifiNote: String
        var usbHubNote: String
        var qm2Note: String
        var bridgeNote: String
    }

    func collectSnap() -> Snap {
        let muxRaw = Self.run("/bin/bash", ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; if [ -x \(kIdevice) ]; then \(kIdevice) -l; else idevice_id -l; fi"])
        let mux = muxRaw.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.isEmpty && !$0.contains("ERROR") && !$0.contains("No device") }
        let ioreg = Self.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0"])
        let usbPhone = ioreg.range(of: "iPhone", options: .caseInsensitive) != nil
        let en9 = Self.run("/sbin/ifconfig", ["en9"])
        let en9Up = en9.contains("status: active")
        let en1 = Self.run("/sbin/ifconfig", ["en1"])
        let en1Up = en1.contains("status: active")
        let en8 = Self.run("/sbin/ifconfig", ["en8"])
        let en8Up = en8.contains("status: active")
        let labNetPresent = en8.contains("10.42.")
        let usbLoc = ioreg.contains("iPhone@02116000")
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
        let extra = Self.householdNotes(en1: en1, en1Up: en1Up, en8: en8, en8Up: en8Up, labNet: labNetPresent, usbLoc: usbLoc, bridgeCode: bridgeCode, ioreg: ioreg)
        return Snap(
            mux: mux, usbPhone: usbPhone, en9Up: en9Up, drives: drives, diskutilHead: diskHead,
            tokenPresent: tokenPresent, pageCode: pageCode, blochCode: blochCode, bridgeCode: bridgeCode,
            phoneUsed: phoneUsed, phoneFree: phoneFree, phoneKnown: phoneKnown, tools: tools,
            latestStamp: latest, vaultExists: vaultExists, liveJpg: liveJpg, afcUp: false,
            mbpNote: extra.mbp, nestNote: extra.nest, kinectNote: extra.kinect, consoleNote: extra.console,
            wifiNote: extra.wifi, usbHubNote: extra.usbhub, qm2Note: extra.qm2, bridgeNote: extra.bridge
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

        if let vault = s.drives.first(where: { $0.mount == "/Volumes/MacBookPro - Data" }) {
            selectedMount = vault.mount
        }
        lastPhoneUsed = s.phoneUsed
        lastPhoneFree = s.phoneFree
        lastPhoneKnown = s.phoneKnown
        lastMBPNote = s.mbpNote
        lastNestNote = s.nestNote
        lastKinectNote = s.kinectNote
        lastConsoleNote = s.consoleNote
        lastWifiNote = s.wifiNote
        lastUSBHubNote = s.usbHubNote
        lastQm2Note = s.qm2Note
        lastBridgeNote = s.bridgeNote
        for tile in logoTiles {
            tile.toolTip = tile.item.subtitle + " · " + Self.tileStatus(id: tile.item.id, snap: s)
        }
        applyParts(phoneUsed: s.phoneUsed, phoneFree: s.phoneFree, phoneKnown: s.phoneKnown)
        rebuildStorageBars()
        refreshIdentity()
        refreshThumbs()
        if isoList != nil { applyISOLists() }
        rebuildRoutes(s)
        applyMotion(s)
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

    struct HouseNotes {
        var mbp: String
        var nest: String
        var kinect: String
        var console: String
        var wifi: String
        var usbhub: String
        var qm2: String
        var bridge: String
    }

    static func scrubLaptopIP(_ s: String) -> String {
        return s.replacingOccurrences(of: "192.168.0.104", with: ".89")
    }

    static func jsonFile(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func householdNotes(en1: String, en1Up: Bool, en8: String, en8Up: Bool, labNet: Bool, usbLoc: Bool, bridgeCode: String, ioreg: String) -> HouseNotes {
        let home = NSHomeDirectory()
        var mbp = "2019 MBP not in machines.json · SSH not started"
        if let obj = jsonFile(home + "/.grok/pool/hotpipe/machines.json"), let hosts = obj["hosts"] as? [[String: Any]] {
            if let h = hosts.first(where: { ($0["id"] as? String) == "grokpool-laptop" }) {
                let up = h["up"] as? Bool ?? false
                let via = scrubLaptopIP(h["via"] as? String ?? "")
                let err = h["err"] as? String ?? ""
                mbp = "machines.json grokpool-laptop · 2019-mbp · via \(via) · \(up ? "up" : "peer down") · \(err) · SSH not started"
            }
        }
        let arp = run("/usr/sbin/arp", ["-an"])
        if arp.contains("192.168.0.89") {
            mbp += " · arp cache has .89"
        }

        var nest = "old Nest camera · last file missing"
        if let obj = jsonFile(home + "/.panda/mg-governance/LATEST-nest-cam.json") {
            let seen = obj["seen"] as? Bool ?? false
            let stamp = obj["stamp_utc"] as? String ?? "?"
            let model = obj["model"] as? String ?? "Nest"
            nest = "\(model) · seen \(seen) · stamp \(stamp) · not live"
        }

        var kinect = "leftover Xbox Kinect · USB dark"
        if let obj = jsonFile(home + "/.grok/pool/hotpipe/cams.json"), let k = obj["kinect"] as? [String: Any] {
            let honest = (k["honest"] as? String) ?? "Kinect USB dark"
            kinect = honest
        } else if ioreg.range(of: "Kinect", options: .caseInsensitive) != nil || ioreg.contains("NUI") {
            kinect = "Kinect/NUI string present in IOUSB"
        } else {
            kinect = "leftover Xbox Kinect · not on USB now (cams.json / IOUSB dark)"
        }

        var console = "game console · not labeled on LAN snapshot"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: home + "/.panda/mg-governance/LATEST-lan-devices.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let devices = obj["devices"] as? [[String: Any]] {
            let stamp = obj["stamp_utc"] as? String ?? "?"
            if let n = devices.first(where: { (($0["mac"] as? String) ?? "").lowercased().hasPrefix("94:8e:6d") }) {
                let ip = n["ip"] as? String ?? "?"
                let ping = n["ping_alive"] as? Bool ?? false
                console = "Nintendo OUI 94:8e:6d in LATEST-lan-devices.json \(stamp) · \(ip) · ping \(ping) · not in a new scan"
            } else {
                console = "no Nintendo OUI in LATEST-lan-devices.json \(stamp) · household console not identified"
            }
        }

        var en1ip = ""
        for line in en1.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("inet ") && !t.contains("inet6") {
                en1ip = t.replacingOccurrences(of: "inet ", with: "").components(separatedBy: " ").first ?? ""
            }
        }
        let wifi = en1Up ? "en1 up · Chariot house wifi · \(en1ip.isEmpty ? "ip unknown" : "this Mini \(en1ip)") · SSID not printed" : "en1 down · Chariot path not associated"

        let usbhub = usbLoc ? "USB2 hub tree · iPhone@02116000 present" : "iPhone@02116000 not in IOUSB right now"

        var qm2 = "AirPort Express Qm-2 · en8 "
        if !en8Up {
            qm2 += "down · lab gateway not assigned"
        } else if labNet {
            qm2 += "up · lab 10.42 prefix present"
        } else {
            qm2 += "up · link-local only · lab gateway 10.42 not assigned"
        }

        let bridgeUp = bridgeCode != "000" && !bridgeCode.isEmpty
        let bridge = bridgeUp ? "origin_bridge :8798 up (gated, token not printed)" : "origin_bridge :8798 down"

        return HouseNotes(mbp: mbp, nest: nest, kinect: kinect, console: console, wifi: wifi, usbhub: usbhub, qm2: qm2, bridge: bridge)
    }

    static func tileStatus(id: String, snap: Snap) -> String {
        switch id {
        case "baby": return snap.mux.isEmpty ? "mux empty" : "mux up"
        case "brick": return "Continuity · not on mux"
        case "mini": return "this host"
        case "mbp2019": return snap.mbpNote
        case "kinect": return snap.kinectNote
        case "nestcam": return snap.nestNote
        case "wifi": return snap.wifiNote
        case "usbhub": return snap.usbHubNote
        case "qm2": return snap.qm2Note
        case "bridge": return snap.bridgeNote
        case "console": return snap.consoleNote
        case "ble": return "Brick path · no session claimed"
        case "nfc": return "Wallet/Continuity route only · no session"
        case "iso": return "ISO / USB tools"
        case "osimg": return "OS image notes"
        case "models": return "HF / LM Studio"
        case "andslot": return "reserved"
        default: return ""
        }
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
