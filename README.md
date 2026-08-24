# grokbots

Grok Bot **tools seat**. First tool: **fc-preserve**.

Repo: https://github.com/fornevercollective/grokbots

This is not grok-build. Tools live here so the Mini plugin nest stays the live CLI and this repo is the standalone copy.

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

Native AppKit 3-step (not Electron, not SwiftUI, not Etcher):

```bash
open dist/FC-Preserve.app
# sources: fc-preserve/app/   build: fc-preserve/app/build.sh
```


### Devices

| Alias | What | Flash |
|-------|------|-------|
| **GrokBotBaby** | iPhone 7 Plus A10 checkm8, iOS 15.1, UDID `4ea7e05b3045f0e9036275125a85225dd6dd9bb9` | preserve only until `linux-gate.json` `ready: true` |
| **Brick** | daily iPhone | preserve only, **never** flash |

### Production notes (Mini)

- Personal Hotspot / USB-NCM (`en9` `169.254.*`) breaks usbmux. Turn hotspot off, unplug/replug. Do not treat an empty mux list as “no phone”.
- Encrypted iOS backup: `FC_PRESERVE_BACKUP_PASSWORD` (unset = unencrypted).
- Override vault: `FC_PRESERVE_ROOT` (Documents paths are too tight).

See `fc-preserve/README.md`, `commands/preserve.md`, `skills/preserve/SKILL.md`.
