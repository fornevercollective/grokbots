---
name: preserve
description: >
  Device backups, OSINT inventory, and linux-flash gate for GrokBotBaby (and
  other phones). Customizable Phosphor + OpenExtract + IntuneBrew-style vault.
  Triggers: /preserve, fcs preserve, GrokBotBaby, device backup, phone backup,
  OSINT preservation, dump the phone, flash linux on phone, postmarketOS.
---

# preserve · GrokBotBaby vault

Do **not** reimplement backup/extract in chat. Run **`fcs preserve`**.

Local-only vault. Never upload phone content.

## First action

```bash
fcs preserve doctor
fcs preserve probe
```

If probe count is 0: tell the user to unlock **GrokBotBaby**, plug USB, tap Trust, then retry. Do not claim a backup exists.

## Capture everything before linux

```bash
fcs preserve all GrokBotBaby
```

Then read `linux-gate.json` from the printed `run` path. Flash only when `"ready": true`:

```bash
fcs preserve linux GrokBotBaby
```

If the gate is not ready, refuse to walk through flashing. Fix the missing domains instead.

## Other commands

```bash
fcs preserve devices
fcs preserve backup GrokBotBaby
fcs preserve extract GrokBotBaby
fcs preserve catalog GrokBotBaby
fcs preserve osint GrokBotBaby
fcs preserve hash GrokBotBaby
fcs preserve gate GrokBotBaby
```

Direct engine: `python3 /Volumes/qbitOS/00.dev/grokbotsGH/fc-preserve/preserve.py …`

Default vault: `/Volumes/MacBookPro - Data/FC-Preserve/<alias>/<UTC-stamp>/`

## Rules

1. GrokBotBaby (iPhone 7 Plus A10 checkm8 iOS 15.1, UDID `4ea7e05b3045f0e9036275125a85225dd6dd9bb9`) is the default alias — preserve until gate ready. Brick is the daily-driver iPhone — preserve only, never flash. Personal Hotspot / USB-NCM (`en9`) breaks usbmux.
2. Customize domains / flavors in `fc-preserve/config/default.json`.
3. Encrypted iOS backups need `FC_PRESERVE_BACKUP_PASSWORD` or a decrypted Manifest.db.
4. Do not delete vaults. Chain of custody is append-only hashes.
5. postmarketOS / Ubuntu Touch / Droidian wipe userdata. Gate first.
