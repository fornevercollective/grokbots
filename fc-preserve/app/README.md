# FC-Preserve.app

Native **AppKit** desk + 3-step (not Electron, not SwiftUI, not balenaEtcher).

Dark chrome stays: **SELECT DEVICE → SELECT TARGET → BACKUP + verify**.


Window is user-resizable (min ~900×600). Frame persists to `~/.grok/pool/hotpipe/fc-preserve-seat.json`.

Top **SELECT DEVICE** row is a horizontal `NSScrollView`. Each icon+storage bar is one cell. Devices are grouped **Phones | Computers | Storage | Radios | Hubs | IoT/Cameras | Images/Models**. Click a group header to select all in that group.

Left **THUMBNAILS + DATA** is a Finder icon-view: named slots, generic icons, `0 items` empty wells (not gray boxes). Real thumbs if the vault/AFC has images. Click a well to preview in-app (image / video / folder list). Does not open Finder. Multi-selected devices are tabbed Finder panes.

**HOTPIPE** pane (`~/.grok/pool/hotpipe/`) is the multi-device bus: status, push, pull, restart-ingest (Bloch ingest / `qbit-phone-track` only — does not start Elffin, does not pkill MemoryGlass). Shows mux, en9 hotspot, `:8793`, `:8798`. Paths are copyable.

The selected set is a **session**. Backup / target / ISO / motion / hotpipe apply to the checked set. GrokBotBaby + Brick + Mini + vault can be selected together. Brick never flash. Phone flash locked.


Left **SELECT DEVICE** is a multi-select logo grid (phones, Mini, 2019 MBP, storage, cameras, IoT, radios/hubs, ISO, OS images, models). Orange selected, gray idle.

The right **desk** pane is live inventory + tether:

1. **ALL PLUGGED DRIVES** — `diskutil list` + `df` (Internal, MacBookPro, MacBookPro - Data, qbitOS, USB phones, other mounts). Flags capacity / hotspot / mux / dest.
2. **PARTS** — camera, sensors, storage, unique IDs (UDID + serial). Never IMEI or Find My.
3. **STORAGE DISTRIBUTION** — used/free bars for the multi-selected logo set (honest 0 / unknown).
4. **FILE + TOOL ROUTES** — vault, extract/, catalog/, hashes, plus idevice_*/ifuse/AFC/pymobiledevice3/`preserve.py`/ssh. Probe / doctor stream into the desk log. Icon + path + copy. No Terminal hop.
5. **ISO / USB TOOLS** — In-app SELECT IMAGE → TARGET → FLASH + verify. hdiutil / diskutil / asr stream into the desk log. Never iPhone / Internal / vault / qbitOS. No Etcher hop. Phone linux-gate still locks phone flash.
6. **OS IMAGE MANAGEMENT** — Create / Customize / Deploy notes + images/catalog.json. Not zero-touch wipe. Not ManageEngine.
7. **MODELS** — local Hugging Face hub + LM Studio cache browse / pin / remove-from-list. Optional `hf` scan stdout stays in the pane. No download. No Open LM Studio.
8. **AND…** — reserved next lane.
9. **MOTION / TETHER** — WKWebView inside the app for https://live.ugrad.ai/motion and local Bloch `:8793`. Token from `~/.machines/hub.token` is a cookie/header (never printed). Does not open Safari. Capture button only when mux + `idevicescreenshot` are real.

```bash
./build.sh
open ../../dist/FC-Preserve.app
```

Flash / `linux` is never invoked. Gate is not ready.
