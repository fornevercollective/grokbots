# Credits · grokbots / fc-preserve

| | |
|--|--|
| **Product** | grokbots tools seat — first tool `fc-preserve` |
| **Version** | see `VERSION` |
| **Feature** | device backup + OSINT inventory + linux-flash gate |
| **Repo** | https://github.com/fornevercollective/grokbots |

## Ownership

| Layer | Owner |
|-------|--------|
| fc-preserve + grokbots tools seat | **fornevercollective** |
| Live Mini CLI this copy was taken from | Mini plugin at `plugins/fc-media-suite/preserve` (working tree; not committed here) |

## Third-party tools (runtime)

| Tool | Role |
|------|------|
| **libimobiledevice** (`idevice_id` / `ideviceinfo` / `idevicebackup2`) | iOS USB probe + backup2 |
| **adb** | Android / linux-test probe + pull |

## Inspired by (not vendored)

| Project | License | What we used |
|---------|---------|--------------|
| [Phosphor](https://github.com/momenbasel/Phosphor) | MIT | iOS backup + Manifest.db domain model |
| [OpenExtract](https://github.com/charleswest775/openextract) | MIT | message/contact/photo export from backups |
| [IntuneBrew](https://github.com/ugurkocde/IntuneBrew) | MIT | per-app JSON catalog shape |
