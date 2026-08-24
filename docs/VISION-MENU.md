# Vision menu contract

The **tree is the menu**. A visionOS ornament / window menu does not invent
its own inventory. It loads the last snapshot written by the Rust sitter:

```
~/.grok/pool/hotpipe/fc-preserve-tree.json
```

Schema id: `fc-preserve-tree/v1`.

This repo does **not** ship a visionOS / xros binary. Tad's Mac mini has
Command Line Tools only — no full Xcode, no visionOS SDK — so a Vision Pro
`.app` cannot be built here. Menu-ready means the JSON contract is stable
and loadable on another machine (or later over HTTP). Paint can wait.

## Stack

| Layer | Where | Role |
|-------|--------|------|
| `crates/fc-preserve-core` | any macOS / Linux host | walk + sit, no AppKit |
| `crates/fc-preserve` (`fc-preserve`) | same | CLI: `walk` / `sit` / `tree` / `devices` |
| `dist/FC-Preserve.app` | Mini only | optional Swift AppKit paint of the same groups |
| visionOS ornament | future, other machine with Xcode + xros SDK | read this JSON (or HTTP) and show the tree as a menu |

Swift is not the portable app. The portable app is the Rust walker/sitter.

## Load

1. **File (now).** Read `~/.grok/pool/hotpipe/fc-preserve-tree.json` on the
   same host the sitter is running, or copy that file onto another machine.
2. **HTTP (later).** A tiny GET of the same JSON. Do not start Elffin or
   bind `:8793` for this. The file is the source of truth until then.

If the file is missing: run `fc-preserve walk` (or `sit`) on the host that
can see the drives / mux / vault. Do not synthesize nodes in the menu.

## Snapshot keys

```json
{
  "schema": "fc-preserve-tree/v1",
  "generated_at": "2026-08-24T22:00:00Z",
  "host": "tadericsonsMini",
  "source": "sit",
  "snapshot_path": "/Users/tref/.grok/pool/hotpipe/fc-preserve-tree.json",
  "groups": [
    { "title": "Phones", "ids": ["baby", "brick"] }
  ],
  "nodes": [
    {
      "id": "baby",
      "kind": "phone",
      "name": "GrokBotBaby",
      "path": "",
      "used": null,
      "free": null,
      "kids": [],
      "selected": true,
      "flashable": false
    }
  ]
}
```

### Node fields (required)

| Field | Type | Notes |
|-------|------|--------|
| `id` | string | stable picker id (`baby`, `brick`, `mini`, …) |
| `kind` | enum | `phone` `desktop` `storage` `radio` `hub` `iot` `camera` `iso` `model` `file` |
| `name` | string | display label |
| `path` | string | mount, UDID, or file path. Empty when unknown. |
| `used` | u64 or null | bytes. **null = unknown**. Never invent a size. |
| `free` | u64 or null | bytes. **null = unknown**. |
| `kids` | array of nodes | submenu. Honest empty `[]` when nothing is there. |
| `selected` | bool | from the Mini session / seat JSON when present |
| `flashable` | bool | **false** for Brick, any phone, Internal, vault (and qbitOS / MBP vol) |

### Groups (same row as AppKit)

`Phones` · `Computers` · `Storage` · `Radios` · `Hubs` · `IoT` · `Images/Models`

A Vision menu paints one ornament section per group, then one item per id
in `groups[i].ids`, looked up in `nodes`. Nested `kids` become a submenu
(vault stamps, ISO files, models, hotpipe `fc-preserve-*` files).

## Honesty rules

- Mux empty → phones still appear, `used`/`free` stay `null`, `path` empty.
- Vault / volume missing → storage node stays, sizes `null`, `kids` `[]`.
- Images library empty → `iso.kids` is `[]` (catalog.json may still be a file kid).
- Radio / hub / IoT / camera have no fake RSSI or capacity.
- `flashable` is a lock, not a suggestion to flash. Phone flash stays locked
  even if a future HTTP API exists.

## Ornament behaviour (when someone has the SDK)

- Read the JSON on appear + every ~2s (the sitter's period) or on file change.
- Selecting an item sets `selected` locally; writing session state back is
  optional and must not flash, must not start Elffin, must not open `:8793`.
- A `flashable: false` item is shown dimmed / locked. No "flash" action on
  Brick, phones, Internal, or the vault.
- Do not compile this contract into a `.app` on the Mini.

## CLI on any machine with rustc

```bash
fc-preserve walk      # walk + write snapshot + print JSON
fc-preserve sit       # foreground sitter
fc-preserve tree      # print last snapshot
fc-preserve devices   # group listing
```

Binary after `cargo build --release`:

- `target/release/fc-preserve`
- `dist/fc-preserve` (copy on the Mini; `dist/FC-Preserve.app` is the Swift paint and stays)
