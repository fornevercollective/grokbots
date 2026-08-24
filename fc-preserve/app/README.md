# FC-Preserve.app

Native **AppKit** desk + 3-step (not Electron, not SwiftUI, not balenaEtcher).

Dark chrome stays: **SELECT DEVICE → SELECT TARGET → BACKUP + verify**.

The right **desk** pane is live inventory + tether:

1. **ALL PLUGGED DRIVES** — `diskutil list` + `df` (Internal, MacBookPro, MacBookPro - Data, qbitOS, USB phones, other mounts). Flags capacity / hotspot / mux / dest.
2. **PARTS** — camera, sensors, storage, unique IDs (UDID + serial). Never IMEI or Find My.
3. **STORAGE DISTRIBUTION** — used/free bar for the selected volume and the phone (honest 0 if mux empty).
4. **FILE + TERMINAL ROUTES** — vault, extract/, catalog/, hashes, plus idevice_*/ifuse/AFC/pymobiledevice3/`preserve.py`/ssh. Icon + path + copy.
5. **MOTION / TETHER** — https://live.ugrad.ai/motion, local Bloch viewer `:8793` status only (does not start Elffin), token-file present / page reachable / ingest up. Capture button only when mux + `idevicescreenshot` are real.

```bash
./build.sh
open ../../dist/FC-Preserve.app
```

Flash / `linux` is never invoked. Gate is not ready.
