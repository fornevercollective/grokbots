# FC-Preserve.app

Native **AppKit** desk + 3-step (not Electron, not SwiftUI, not balenaEtcher).

Dark chrome stays: **SELECT DEVICE → SELECT TARGET → BACKUP + verify**.


Window is user-resizable (min ~900×600). Frame persists to `~/.grok/pool/hotpipe/fc-preserve-seat.json`.

Top **SELECT DEVICE** row is a horizontal `NSScrollView`. Each icon+storage bar is one cell. Devices are grouped **Phones | Computers | Storage | Radios | Hubs | IoT/Cameras | Images/Models**. Click a group header to select all in that group.

Left **THUMBNAILS + DATA** is a Finder icon-view: named slots, generic icons, `0 items` empty wells (not gray boxes). Real thumbs if the vault/AFC has images. Double-click opens Finder. Multi-selected devices are tabbed Finder panes.

**HOTPIPE** pane (`~/.grok/pool/hotpipe/`) is the multi-device bus: status, push, pull, restart-ingest (Bloch ingest / `qbit-phone-track` only — does not start Elffin, does not pkill MemoryGlass). Shows mux, en9 hotspot, `:8793`, `:8798`. Paths are copyable.

The selected set is a **session**. Backup / target / ISO / motion / hotpipe apply to the checked set. GrokBotBaby + Brick + Mini + vault can be selected together. Brick never flash. Phone flash locked.


Left **SELECT DEVICE** is a multi-select logo grid (phones, Mini, 2019 MBP, storage, cameras, IoT, radios/hubs, ISO, OS images, models). Orange selected, gray idle.

The right **desk** pane is live inventory + tether:

1. **ALL PLUGGED DRIVES** — `diskutil list` + `df` (Internal, MacBookPro, MacBookPro - Data, qbitOS, USB phones, other mounts). Flags capacity / hotspot / mux / dest.
2. **PARTS** — camera, sensors, storage, unique IDs (UDID + serial). Never IMEI or Find My.
3. **STORAGE DISTRIBUTION** — used/free bars for the multi-selected logo set (honest 0 / unknown).
4. **FILE + TERMINAL ROUTES** — vault, extract/, catalog/, hashes, plus idevice_*/ifuse/AFC/pymobiledevice3/`preserve.py`/ssh. Icon + path + copy.
5. **ISO / USB TOOLS** — Etcher-shaped SELECT IMAGE → TARGET → FLASH + verify. Library under FC-Preserve/images/. Never iPhone / Internal / vault / qbitOS. Open Etcher is a route, not auto-flash. Phone linux-gate still locks phone flash.
6. **OS IMAGE MANAGEMENT** — Create / Customize / Deploy notes + images/catalog.json. Not zero-touch wipe. Not ManageEngine.
7. **MODELS** — local Hugging Face hub + LM Studio dir. No download. No second GPU host.
8. **AND…** — reserved next lane.
9. **MOTION / TETHER** — https://live.ugrad.ai/motion, local Bloch viewer `:8793` status only (does not start Elffin), token-file present / page reachable / ingest up. Capture button only when mux + `idevicescreenshot` are real.

```bash
./build.sh
open ../../dist/FC-Preserve.app
```

Flash / `linux` is never invoked. Gate is not ready.
