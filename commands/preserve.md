# /preserve — device backup, OSINT, linux-flash gate

Dump **GrokBotBaby** (or any USB phone) to a local vault before flashing linux.

```text
/preserve                 probe USB phones
/preserve all             backup + extract + catalog + hash + gate
/preserve linux           flash notes only if gate is ready
```

Shell:

```bash
fcs preserve doctor
fcs preserve probe
fcs preserve all GrokBotBaby
fcs preserve linux GrokBotBaby
```

Vault: `/Volumes/MacBookPro - Data/FC-Preserve/GrokBotBaby/<stamp>/`

**GrokBotBaby** = iPhone 7 Plus A10 checkm8 iOS 15.1 (UDID `4ea7e05b3045f0e9036275125a85225dd6dd9bb9`) — preserve until gate ready.
**Brick** = daily iPhone — preserve only, never flash.
Personal Hotspot / USB-NCM (`en9`) breaks usbmux — turn hotspot off.

Do not flash until `linux-gate.json` has `"ready": true`.
