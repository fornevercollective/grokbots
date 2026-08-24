# FC-Preserve.app

Native **AppKit** 3-step (not Electron, not SwiftUI, not balenaEtcher).

1. **SELECT DEVICE** — GrokBotBaby (iPhone 7 Plus, default) or Brick (daily, never flash). Live USB via `idevice_id -l` / `preserve.py probe`.
2. **SELECT TARGET** — default `/Volumes/MacBookPro - Data/FC-Preserve`. Refuses `~/Documents` (Internal too tight) and `/Volumes/qbitOS` (lab SSD, not the vault).
3. **BACKUP + verify** — `python3 fc-preserve/preserve.py all <alias>`. Flash stays locked.

```bash
./build.sh
open ../../dist/FC-Preserve.app
```

Flash / `linux` is never invoked. Gate is not ready.
