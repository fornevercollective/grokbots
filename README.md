# grokbots

Grok Bot **tools seat**. First tool: **fc-preserve**.

Repo: https://github.com/fornevercollective/grokbots

This is not grok-build. Tools live here so the Mini plugin nest stays the live CLI and this repo is the standalone copy.

## Stack

| Layer | Portable? | Role |
|-------|-----------|------|
| **Rust core** `crates/fc-preserve-core` | yes (macOS + Linux) | **walk** a device/vault/host tree; **sit** and write `~/.grok/pool/hotpipe/fc-preserve-tree.json` |
| **Rust CLI** `crates/fc-preserve` (`fc-preserve`) | yes | `walk` / `sit` / `tree` / `devices` / `backup` / `all` / `ready` |
| **Swift AppKit** `dist/FC-Preserve.app` | Mini only | optional paint of the same groups. Keep it running; do not delete it. |
| **visionOS menu** | future | ornament that **reads the tree JSON** (or HTTP later). No visionOS binary in this repo — Mini has CLT only, no xros SDK. |

**Swift is not the portable app.** The portable app is the Rust walker/sitter. The tree JSON is the Vision-menu contract (`docs/VISION-MENU.md`). Menu-ready means the tree is the menu.

```bash
cargo build --release
./target/release/fc-preserve walk
./target/release/fc-preserve sit      # foreground sitter, writes the JSON
./target/release/fc-preserve tree     # print last snapshot
./target/release/fc-preserve devices
./target/release/fc-preserve backup   # python3 <repo>/fc-preserve/preserve.py backup GrokBotBaby
./target/release/fc-preserve all      # backup → extract → catalog → hash → gate
./target/release/fc-preserve ready    # honest mux/pair/en9; ready:true only if UDID
# copy also lands at dist/fc-preserve  (AppKit app stays at dist/FC-Preserve.app)
```

Workspace members: `crates/fc-preserve-core`, `crates/fc-preserve`. No AppKit in core. `notify` is optional; sit always polls every 2s.

## fc-preserve (Etcher 3-step)

1. **SELECT DEVICE** — live USB (iOS `idevice_id` / Android `adb`).
2. **SELECT TARGET** — vault root. Default is `/Volumes/MacBookPro - Data/FC-Preserve`. Not Internal (`~/Documents`), not qbitOS.
3. **BACKUP + verify** — backup → extract → catalog → SHA-256 → `linux-gate.json`. Flash notes only if `gate.ready` is true.

```bash
fcs preserve                 # probe
fcs preserve doctor
fcs preserve devices
fcs preserve all GrokBotBaby
fcs preserve backup Brick    # daily iPhone — preserve only, never flash
fcs preserve linux GrokBotBaby
python3 fc-preserve/preserve.py --help
```

CLI: `scripts/fcs` → `python3 fc-preserve/preserve.py`.

Native AppKit 3-step + inventory/tether desk (Mini paint only, not Electron, not SwiftUI, not Etcher):

```bash
open dist/FC-Preserve.app
# sources: fc-preserve/app/   build: fc-preserve/app/build.sh
```

### Devices

| Alias | What | Flash |
|-------|------|-------|
| **GrokBotBaby** | iPhone 7 Plus A10 checkm8, iOS 15.1, UDID `4ea7e05b3045f0e9036275125a85225dd6dd9bb9` | preserve only until `linux-gate.json` `ready: true` |
| **Brick** | daily iPhone | preserve only, **never** flash |

Groups (Rust tree + AppKit row): **Phones · Computers · Storage · Radios · Hubs · IoT · Images/Models**.

### Production notes (Mini)

- Personal Hotspot / USB-NCM (`en9` `169.254.*`) breaks usbmux. Turn hotspot off, unplug/replug. Do not treat an empty mux list as “no phone”.
- Encrypted iOS backup: `FC_PRESERVE_BACKUP_PASSWORD` (unset = unencrypted).
- Override vault: `FC_PRESERVE_ROOT` (Documents paths are too tight).
- Mini has Command Line Tools only — no full Xcode, no visionOS SDK. Do not try to build a Vision Pro `.app` here.

See `fc-preserve/README.md`, `commands/preserve.md`, `skills/preserve/SKILL.md`, `docs/VISION-MENU.md`.
