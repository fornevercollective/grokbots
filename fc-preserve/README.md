# fc-preserve

Local device **backup + OSINT inventory + linux-flash gate**.

A customizable fornevercollective version of:

| Upstream | What we took |
|----------|----------------|
| [Phosphor](https://github.com/momenbasel/Phosphor) | USB device probe, full local backup, Manifest.db domain browse, no iCloud |
| [OpenExtract](https://github.com/charleswest775/openextract) | Messages / contacts / photos / notes / calls export from a backup |
| [IntuneBrew](https://github.com/ugurkocde/IntuneBrew) | Per-app JSON catalog (`catalog/Apps/<bundleId>.json`) you can edit |

Not a fork. No Electron, no SwiftUI, no Intune. CLI + JSON vault. Stdlib Python + `idevicebackup2` / `adb`.

Native **AppKit** 3-step lives in `app/` and builds `dist/FC-Preserve.app` (`ai.qbitos.fc-preserve`). Flash stays locked.

Default target: **GrokBotBaby** — preserve every byte locally before flashing a linux flavor for testing.

## Commands

```bash
fcs preserve doctor
fcs preserve probe                 # USB iOS + Android
fcs preserve devices               # alias registry
fcs preserve all GrokBotBaby       # backup → extract → catalog → hash → gate
fcs preserve linux GrokBotBaby     # flash notes ONLY if gate is ready
```

Pieces, if you want them one at a time:

```bash
fcs preserve backup GrokBotBaby
fcs preserve extract GrokBotBaby
fcs preserve catalog GrokBotBaby
fcs preserve osint GrokBotBaby
fcs preserve hash GrokBotBaby
fcs preserve gate GrokBotBaby
```

Direct:

```bash
python3 fc-preserve/preserve.py all GrokBotBaby
```

## Vault layout

`/Volumes/MacBookPro - Data/FC-Preserve/GrokBotBaby/<UTC-stamp>/`

```
device.json              identity + alias metadata
probe.json               USB snapshot
backup/                  raw idevicebackup2 UDID tree  or  adb dump
extract/                 parsed domains (messages, photos, contacts, …)
catalog/apps.json        all installed apps
catalog/Apps/*.json      IntuneBrew-style one-file-per-app formulas
osint/inventory.json     serial / model / OS / warnings
hashes.sha256            chain of custody
chain-of-custody.json
linux-gate.json          ready=true required before any flash
summary.json
```

Nothing leaves the machine.

## GrokBotBaby → linux

1. Unlock the phone. USB. Trust this computer.
2. `fcs preserve all GrokBotBaby`
3. Wait until `linux-gate.json` has `"ready": true`.
4. Only then `fcs preserve linux GrokBotBaby` — prints the flavor URL and a wipe warning.
5. Flash. The vault stays; the phone does not.

Default flavor is `postmarketos` (Android hardware). Change it in `config/default.json`.

iPhone Linux (Project Sandcastle) is experimental and is **not** treated as a supported daily OS. Brick (Continuity iPhone) is marked do-not-flash.

## Customize

Edit `fc-preserve/config/default.json` (or point `FC_PRESERVE_CONFIG` at your copy):

- `devices` — aliases, linux flavor, what to pull
- `domains.ios` / `domains.android` — extract list (required vs optional)
- `linux_flavors` — add your own image notes
- `gate.required_extract_ids` — what must exist before flash

Env:

| Var | Role |
|-----|------|
| `FC_PRESERVE_ROOT` | vault root (default `/Volumes/MacBookPro - Data/FC-Preserve`) |
| `FC_PRESERVE_CONFIG` | config JSON |
| `FC_PRESERVE_BACKUP_PASSWORD` | enable iOS encrypted backup (more domains, including keychain) |

## Host tools

```bash
brew install libimobiledevice      # ideviceinfo, idevicebackup2
# Android
# Android platform-tools: adb
```

Encrypted iOS backups: Manifest.db is ciphertext until unlocked. Re-run extract after decrypting, or set the password env before `backup`.

## Tests

```bash
python3 fc-preserve/tests/test_preserve.py
```

## Mini production notes

- **GrokBotBaby** — iPhone 7 Plus A10 checkm8, iOS 15.1, UDID `4ea7e05b3045f0e9036275125a85225dd6dd9bb9`. Preserve until `linux-gate.json` `ready: true`.
- **Brick** — daily iPhone. Preserve only, never flash.
- Personal Hotspot / USB-NCM (`en9`) breaks usbmux. Turn hotspot off, unplug/replug.
- Vault is the Data volume, not Internal, not qbitOS.
