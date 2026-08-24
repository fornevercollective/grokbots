#!/usr/bin/env python3
"""fc-preserve — device backup, OSINT inventory, and linux-flash gate.

Inspired by (not a fork of):
  Phosphor     https://github.com/momenbasel/Phosphor
  OpenExtract  https://github.com/charleswest775/openextract
  IntuneBrew   https://github.com/ugurkocde/IntuneBrew

Local-only. Never uploads. Customize via preserve/config/default.json
or FC_PRESERVE_CONFIG. Stdlib + host CLIs (ideviceinfo, idevicebackup2, adb).
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE / "config" / "default.json"
TOOL_VERSION = "0.1.0"
APPLE_EPOCH = 978307200  # 2001-01-01 UTC


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def expand(p: str | Path) -> Path:
    return Path(os.path.expanduser(str(p))).resolve()


def load_config(path: Path | None = None) -> dict[str, Any]:
    cfg_path = path or Path(os.environ.get("FC_PRESERVE_CONFIG", DEFAULT_CONFIG))
    data = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    env_root = os.environ.get("FC_PRESERVE_ROOT")
    if env_root:
        data["vault_root"] = env_root
    return data


def vault_root(cfg: dict[str, Any]) -> Path:
    return expand(cfg.get("vault_root", "~/Documents/FC-Preserve"))


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")


def run(cmd: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def which(name: str) -> str | None:
    return shutil.which(name)


def sha256_file(path: Path, chunk: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def resolve_alias(cfg: dict[str, Any], name: str | None) -> str:
    if not name:
        return str(cfg.get("default_device") or "GrokBotBaby")
    key = name.strip()
    devices = cfg.get("devices") or {}
    if key in devices:
        return key
    lower = key.lower()
    for did, meta in devices.items():
        aliases = [a.lower() for a in (meta.get("aliases") or [])]
        if lower == did.lower() or lower in aliases:
            return did
    return key


def device_meta(cfg: dict[str, Any], alias: str) -> dict[str, Any]:
    return dict((cfg.get("devices") or {}).get(alias) or {})


# ── probe ──────────────────────────────────────────────────────────────────


def parse_ideviceinfo(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


def probe_ios() -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    idevice_id = which("idevice_id")
    ideviceinfo = which("ideviceinfo")
    if not idevice_id:
        return devices
    listing = run([idevice_id, "-l"])
    udids = [ln.strip() for ln in listing.stdout.splitlines() if ln.strip()]
    for udid in udids:
        info: dict[str, str] = {"UniqueDeviceID": udid}
        if ideviceinfo:
            raw = run([ideviceinfo, "-u", udid])
            if raw.returncode == 0:
                info.update(parse_ideviceinfo(raw.stdout))
            else:
                info["_error"] = (raw.stderr or raw.stdout).strip()[:400]
        devices.append(
            {
                "platform": "ios",
                "udid": udid,
                "name": info.get("DeviceName") or info.get("DeviceClass") or "iOS",
                "model": info.get("ProductType") or "",
                "os": info.get("ProductVersion") or "",
                "serial": info.get("SerialNumber") or "",
                "imei": info.get("InternationalMobileEquipmentIdentity") or "",
                "connection": "usb",
                "raw": info,
            }
        )
    return devices


def parse_adb_devices(text: str) -> list[str]:
    serials: list[str] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            serials.append(parts[0])
    return serials


def adb_prop(serial: str, key: str) -> str:
    r = run(["adb", "-s", serial, "shell", "getprop", key])
    return (r.stdout or "").strip()


def probe_android() -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    if not which("adb"):
        return devices
    listing = run(["adb", "devices", "-l"])
    for serial in parse_adb_devices(listing.stdout):
        devices.append(
            {
                "platform": "android",
                "udid": serial,
                "name": adb_prop(serial, "ro.product.device") or serial,
                "model": adb_prop(serial, "ro.product.model"),
                "os": adb_prop(serial, "ro.build.version.release"),
                "serial": adb_prop(serial, "ro.serialno") or serial,
                "imei": "",
                "connection": "usb",
                "raw": {
                    "manufacturer": adb_prop(serial, "ro.product.manufacturer"),
                    "brand": adb_prop(serial, "ro.product.brand"),
                    "fingerprint": adb_prop(serial, "ro.build.fingerprint"),
                    "sdk": adb_prop(serial, "ro.build.version.sdk"),
                    "hardware": adb_prop(serial, "ro.hardware"),
                    "codename": adb_prop(serial, "ro.product.device"),
                },
            }
        )
    return devices


def probe_all() -> dict[str, Any]:
    ios = probe_ios()
    android = probe_android()
    return {
        "captured_at": utcnow(),
        "host": os.uname().nodename if hasattr(os, "uname") else "",
        "tools": {
            "idevice_id": which("idevice_id"),
            "ideviceinfo": which("ideviceinfo"),
            "idevicebackup2": which("idevicebackup2"),
            "adb": which("adb"),
            "pymobiledevice3": which("pymobiledevice3"),
        },
        "ios": ios,
        "android": android,
        "count": len(ios) + len(android),
    }


def pick_device(probe: dict[str, Any], want_platform: str | None = None) -> dict[str, Any] | None:
    pool = []
    if want_platform in (None, "auto", "ios"):
        pool.extend(probe.get("ios") or [])
    if want_platform in (None, "auto", "android"):
        pool.extend(probe.get("android") or [])
    if not pool:
        return None
    if len(pool) == 1:
        return pool[0]
    # Prefer USB android for linux-test (flashable) if both present.
    android = [d for d in pool if d.get("platform") == "android"]
    if android:
        return android[0]
    return pool[0]


# ── backup ─────────────────────────────────────────────────────────────────


def new_run_dir(cfg: dict[str, Any], alias: str) -> Path:
    root = vault_root(cfg) / alias / stamp()
    for sub in ("backup", "extract", "catalog", "osint", "media", "logs"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    return root


def latest_run(cfg: dict[str, Any], alias: str) -> Path | None:
    base = vault_root(cfg) / alias
    if not base.is_dir():
        return None
    runs = sorted([p for p in base.iterdir() if p.is_dir()], reverse=True)
    return runs[0] if runs else None


def backup_ios(device: dict[str, Any], run_dir: Path, encrypted: bool) -> dict[str, Any]:
    tool = which("idevicebackup2")
    if not tool:
        return {"ok": False, "error": "idevicebackup2 not installed (brew install libimobiledevice)"}
    dest = run_dir / "backup"
    dest.mkdir(parents=True, exist_ok=True)
    udid = device["udid"]
    password = os.environ.get("FC_PRESERVE_BACKUP_PASSWORD")
    log_path = run_dir / "logs" / "idevicebackup2.log"
    if encrypted and password:
        enc = run([tool, "-u", udid, "encryption", "on", password], timeout=60)
        (run_dir / "logs" / "encryption-on.log").write_text(enc.stdout + enc.stderr, encoding="utf-8")
    cmd = [tool, "-u", udid, "backup", "--full", str(dest)]
    proc = run(cmd, timeout=6 * 60 * 60)
    log_path.write_text((proc.stdout or "") + "\n" + (proc.stderr or ""), encoding="utf-8")
    # idevicebackup2 writes <dest>/<UDID>/
    udid_dir = dest / udid
    ok = proc.returncode == 0 and (udid_dir / "Manifest.plist").exists()
    return {
        "ok": ok,
        "platform": "ios",
        "command": cmd,
        "returncode": proc.returncode,
        "path": str(udid_dir if udid_dir.exists() else dest),
        "log": str(log_path),
        "error": None if ok else (proc.stderr or proc.stdout or "backup failed")[:800],
    }


def backup_android(device: dict[str, Any], run_dir: Path, include_sdcard: bool) -> dict[str, Any]:
    if not which("adb"):
        return {"ok": False, "error": "adb not installed"}
    serial = device["udid"]
    dest = run_dir / "backup"
    dest.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []

    def adb(*args: str, timeout: int = 120) -> str:
        r = run(["adb", "-s", serial, *args], timeout=timeout)
        if r.returncode != 0:
            errors.append(f"{' '.join(args)}: {(r.stderr or r.stdout)[:300]}")
        return r.stdout or ""

    (dest / "getprop.txt").write_text(adb("shell", "getprop"), encoding="utf-8", errors="replace")
    (dest / "packages-all.txt").write_text(adb("shell", "pm", "list", "packages", "-f"), encoding="utf-8")
    (dest / "packages-3rd.txt").write_text(adb("shell", "pm", "list", "packages", "-3"), encoding="utf-8")
    (dest / "features.txt").write_text(adb("shell", "pm", "list", "features"), encoding="utf-8")
    for name in ("account", "wifi", "telephony.registry", "package", "usagestats"):
        (dest / f"dumpsys-{name}.txt").write_text(
            adb("shell", "dumpsys", name, timeout=180), encoding="utf-8", errors="replace"
        )
    if include_sdcard:
        sd = dest / "sdcard"
        sd.mkdir(exist_ok=True)
        pull = run(["adb", "-s", serial, "pull", "/sdcard", str(sd)], timeout=6 * 60 * 60)
        (run_dir / "logs" / "adb-pull-sdcard.log").write_text(
            (pull.stdout or "") + "\n" + (pull.stderr or ""), encoding="utf-8"
        )
        if pull.returncode != 0:
            errors.append("adb pull /sdcard failed — unlock phone, grant file access")
    ok = (dest / "packages-all.txt").stat().st_size > 0
    return {
        "ok": ok,
        "platform": "android",
        "path": str(dest),
        "errors": errors,
        "error": None if ok else "; ".join(errors) or "android backup failed",
    }


# ── iOS extract ────────────────────────────────────────────────────────────


def find_ios_backup_root(backup_dir: Path) -> Path | None:
    if (backup_dir / "Manifest.db").exists() or (backup_dir / "Manifest.plist").exists():
        return backup_dir
    for child in sorted(backup_dir.iterdir()) if backup_dir.is_dir() else []:
        if child.is_dir() and ((child / "Manifest.db").exists() or (child / "Info.plist").exists()):
            return child
    return None


def blob_path(backup_root: Path, file_id: str) -> Path:
    return backup_root / file_id[:2] / file_id


def is_sha1_id(file_id: str) -> bool:
    return bool(re.fullmatch(r"[0-9a-f]{40}", file_id))


def load_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as f:
        data = plistlib.load(f)
    return data if isinstance(data, dict) else {"_value": data}


def apple_time_to_iso(raw: Any) -> str | None:
    try:
        n = float(raw)
    except (TypeError, ValueError):
        return None
    if n > 1e12:
        n = n / 1_000_000_000.0
    elif n > 1e9:
        n = n / 1_000.0
    try:
        return datetime.fromtimestamp(n + APPLE_EPOCH, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (OSError, OverflowError, ValueError):
        return None


def copy_manifest_file(backup_root: Path, file_id: str, dest: Path) -> bool:
    if not is_sha1_id(file_id):
        return False
    src = blob_path(backup_root, file_id)
    if not src.is_file():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    return True


def extract_ios(backup_root: Path, extract_dir: Path, cfg: dict[str, Any]) -> dict[str, Any]:
    extract_dir.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {"platform": "ios", "backup": str(backup_root), "domains": {}, "missing": []}
    info_plist = backup_root / "Info.plist"
    manifest_plist = backup_root / "Manifest.plist"
    if info_plist.exists():
        shutil.copy2(info_plist, extract_dir / "Info.plist")
        try:
            report["info"] = {
                k: load_plist(info_plist).get(k)
                for k in (
                    "Device Name",
                    "Product Name",
                    "Product Type",
                    "Product Version",
                    "Serial Number",
                    "Unique Identifier",
                    "IMEI",
                    "Phone Number",
                    "Last Backup Date",
                    "Display Name",
                )
            }
        except Exception as exc:
            report["info_error"] = str(exc)
    if manifest_plist.exists():
        shutil.copy2(manifest_plist, extract_dir / "Manifest.plist")
        try:
            mp = load_plist(manifest_plist)
            report["encrypted"] = bool(mp.get("IsEncrypted"))
            apps = mp.get("Applications") or {}
            report["app_count"] = len(apps) if isinstance(apps, dict) else 0
        except Exception as exc:
            report["manifest_plist_error"] = str(exc)

    db_path = backup_root / "Manifest.db"
    if not db_path.exists():
        report["missing"].append("Manifest.db")
        report["hint"] = "Encrypted backups hide Manifest.db. Decrypt or re-run with FC_PRESERVE_BACKUP_PASSWORD."
        write_json(extract_dir / "index.json", report)
        return report

    # Detect encrypted sqlite (no SQLite header).
    header = db_path.read_bytes()[:16]
    if not header.startswith(b"SQLite format 3"):
        report["encrypted"] = True
        report["missing"].append("Manifest.db (encrypted)")
        report["hint"] = "Manifest.db is ciphertext. Unlock in Finder or pass backup password."
        write_json(extract_dir / "index.json", report)
        return report

    shutil.copy2(db_path, extract_dir / "Manifest.db")
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        domains = [r[0] for r in conn.execute("SELECT DISTINCT domain FROM Files ORDER BY domain")]
        report["domain_list"] = domains
        write_json(extract_dir / "domains.json", domains)

        def lookup(domain: str, relative: str) -> str | None:
            row = conn.execute(
                "SELECT fileID FROM Files WHERE domain = ? AND relativePath = ? AND flags = 1",
                (domain, relative),
            ).fetchone()
            return row["fileID"] if row else None

        ios_domains = (cfg.get("domains") or {}).get("ios") or []
        for spec in ios_domains:
            did = spec["id"]
            out: dict[str, Any] = {"id": did, "ok": False}
            if spec.get("relative") and spec.get("domain"):
                fid = lookup(spec["domain"], spec["relative"])
                if fid:
                    dest = extract_dir / did / Path(spec["relative"]).name
                    out["ok"] = copy_manifest_file(backup_root, fid, dest)
                    out["file_id"] = fid
                    out["path"] = str(dest) if out["ok"] else None
                else:
                    out["missing"] = f"{spec['domain']}/{spec['relative']}"
            elif spec.get("glob") and spec.get("domain"):
                ext_sql = []
                params: list[str] = [spec["domain"]]
                # glob like *.{jpg,png} → LIKE %.jpg OR ...
                m = re.search(r"\.\{([^}]+)\}", spec["glob"])
                if m:
                    for ext in m.group(1).split(","):
                        ext_sql.append("lower(relativePath) LIKE ?")
                        params.append(f"%.{ext.strip().lower()}")
                where = " OR ".join(ext_sql) if ext_sql else "1=1"
                rows = conn.execute(
                    f"SELECT fileID, relativePath FROM Files WHERE domain = ? AND flags = 1 AND ({where})",
                    params,
                ).fetchall()
                copied = 0
                media_dir = extract_dir / did
                for row in rows:
                    dest = media_dir / Path(row["relativePath"]).name
                    if dest.exists():
                        dest = media_dir / f"{row['fileID'][:8]}-{Path(row['relativePath']).name}"
                    if copy_manifest_file(backup_root, row["fileID"], dest):
                        copied += 1
                out["ok"] = copied > 0
                out["copied"] = copied
            elif spec.get("domain_like"):
                rows = conn.execute(
                    "SELECT fileID, domain, relativePath FROM Files WHERE domain LIKE ? AND relativePath LIKE ? AND flags = 1",
                    (spec["domain_like"], spec.get("relative_like") or "%"),
                ).fetchall()
                copied = 0
                for row in rows:
                    dest = extract_dir / did / Path(row["relativePath"]).name
                    if copy_manifest_file(backup_root, row["fileID"], dest):
                        copied += 1
                out["ok"] = copied > 0
                out["copied"] = copied
            else:
                out["ok"] = True  # identity/manifest handled above
            report["domains"][did] = out
            if spec.get("required") and not out.get("ok") and did not in ("identity", "manifest"):
                report["missing"].append(did)

        # App catalog from AppDomain-* rows
        app_rows = conn.execute(
            "SELECT DISTINCT domain FROM Files WHERE domain LIKE 'AppDomain-%' ORDER BY domain"
        ).fetchall()
        apps = []
        for row in app_rows:
            domain = row[0]
            bundle = domain.removeprefix("AppDomain-")
            n = conn.execute(
                "SELECT COUNT(*) FROM Files WHERE domain = ? AND flags = 1", (domain,)
            ).fetchone()[0]
            apps.append({"bundleId": bundle, "domain": domain, "file_count": n, "type": "app"})
        write_json(extract_dir / "apps-from-manifest.json", apps)
        report["apps_from_manifest"] = len(apps)
    finally:
        conn.close()

    _export_messages(extract_dir)
    _export_contacts(extract_dir)
    write_json(extract_dir / "index.json", report)
    return report


def _export_messages(extract_dir: Path) -> None:
    db = extract_dir / "messages" / "sms.db"
    if not db.exists():
        return
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT m.ROWID as id, m.date as date, m.text as text, m.is_from_me as is_from_me,
                   h.id as handle, m.service as service
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            ORDER BY m.date
            """
        ).fetchall()
    except sqlite3.Error:
        return
    records = []
    for r in rows:
        records.append(
            {
                "id": r["id"],
                "date": apple_time_to_iso(r["date"]),
                "text": r["text"],
                "from_me": bool(r["is_from_me"]),
                "handle": r["handle"],
                "service": r["service"],
            }
        )
    write_json(extract_dir / "messages" / "messages.json", records)
    csv_path = extract_dir / "messages" / "messages.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["id", "date", "from_me", "handle", "service", "text"])
        w.writeheader()
        w.writerows(records)
    conn.close()


def _export_contacts(extract_dir: Path) -> None:
    db = extract_dir / "contacts" / "AddressBook.sqlitedb"
    if not db.exists():
        return
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        people = conn.execute(
            "SELECT ROWID, First, Last, Organization, Nickname FROM ABPerson"
        ).fetchall()
        phones = conn.execute(
            """
            SELECT record_id, value FROM ABMultiValue
            WHERE property = 3
            """
        ).fetchall()
    except sqlite3.Error:
        return
    by_id: dict[int, dict[str, Any]] = {}
    for p in people:
        by_id[p["ROWID"]] = {
            "id": p["ROWID"],
            "first": p["First"],
            "last": p["Last"],
            "org": p["Organization"],
            "nickname": p["Nickname"],
            "phones": [],
        }
    for ph in phones:
        rec = by_id.get(ph["record_id"])
        if rec:
            rec["phones"].append(ph["value"])
    records = list(by_id.values())
    write_json(extract_dir / "contacts" / "contacts.json", records)
    conn.close()


def extract_android(backup_dir: Path, extract_dir: Path) -> dict[str, Any]:
    extract_dir.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {"platform": "android", "backup": str(backup_dir), "domains": {}, "missing": []}
    pkg_file = backup_dir / "packages-all.txt"
    third = backup_dir / "packages-3rd.txt"
    apps = []
    if pkg_file.exists():
        shutil.copy2(pkg_file, extract_dir / "packages-all.txt")
        for line in pkg_file.read_text(encoding="utf-8", errors="replace").splitlines():
            # package:/data/app/.../base.apk=com.foo
            m = re.search(r"package:(?P<path>.+)=(?P<pkg>[\w.]+)\s*$", line)
            if m:
                apps.append({"bundleId": m.group("pkg"), "apk": m.group("path"), "type": "app"})
        report["domains"]["packages"] = {"ok": True, "count": len(apps)}
    else:
        report["missing"].append("packages")
        report["domains"]["packages"] = {"ok": False}
    if third.exists():
        shutil.copy2(third, extract_dir / "packages-3rd.txt")
        report["domains"]["packages_third_party"] = {"ok": True}
    write_json(extract_dir / "apps-from-manifest.json", apps)
    getprop = backup_dir / "getprop.txt"
    if getprop.exists():
        shutil.copy2(getprop, extract_dir / "getprop.txt")
        report["domains"]["identity"] = {"ok": True}
    sd = backup_dir / "sdcard"
    if sd.exists():
        report["domains"]["sdcard"] = {"ok": True, "path": str(sd)}
    else:
        report["missing"].append("sdcard")
        report["domains"]["sdcard"] = {"ok": False}
    write_json(extract_dir / "index.json", report)
    return report


# ── catalog (IntuneBrew-style formulas) ────────────────────────────────────


def build_catalog(run_dir: Path, alias: str, device: dict[str, Any] | None) -> dict[str, Any]:
    apps_path = run_dir / "extract" / "apps-from-manifest.json"
    apps = json.loads(apps_path.read_text(encoding="utf-8")) if apps_path.exists() else []
    formulas = []
    for app in apps:
        bundle = app.get("bundleId") or ""
        formulas.append(
            {
                "name": bundle.rsplit(".", 1)[-1] if bundle else "unknown",
                "bundleId": bundle,
                "description": f"Preserved from {alias}",
                "version": app.get("version") or "unknown",
                "type": "app",
                "platform": (device or {}).get("platform") or "unknown",
                "file_count": app.get("file_count"),
                "apk": app.get("apk"),
                "publisher": bundle.split(".")[0] if "." in bundle else "",
                "source": "fc-preserve",
                "linux_reinstall": None,
            }
        )
    catalog = {
        "device": alias,
        "captured_at": utcnow(),
        "count": len(formulas),
        "apps": formulas,
    }
    write_json(run_dir / "catalog" / "apps.json", catalog)
    # one-file-per-app, IntuneBrew Apps/ layout
    apps_dir = run_dir / "catalog" / "Apps"
    apps_dir.mkdir(parents=True, exist_ok=True)
    for formula in formulas:
        slug = re.sub(r"[^a-z0-9._-]+", "_", formula["bundleId"].lower()) or "unknown"
        write_json(apps_dir / f"{slug}.json", formula)
    return catalog


# ── OSINT inventory ────────────────────────────────────────────────────────


def build_osint(run_dir: Path, alias: str, device: dict[str, Any], extract: dict[str, Any]) -> dict[str, Any]:
    inv = {
        "alias": alias,
        "captured_at": utcnow(),
        "platform": device.get("platform"),
        "udid": device.get("udid"),
        "name": device.get("name"),
        "model": device.get("model"),
        "os": device.get("os"),
        "serial": device.get("serial"),
        "imei": device.get("imei"),
        "extract": {
            "encrypted": extract.get("encrypted"),
            "missing": extract.get("missing"),
            "app_count": extract.get("app_count") or extract.get("apps_from_manifest"),
        },
        "warnings": [],
    }
    if extract.get("encrypted"):
        inv["warnings"].append("Backup is encrypted — some domains not parsed.")
    if device.get("platform") == "ios" and not device.get("imei"):
        inv["warnings"].append("IMEI missing (needs trusted pairing / encrypted backup).")
    write_json(run_dir / "osint" / "inventory.json", inv)
    return inv


# ── chain of custody ───────────────────────────────────────────────────────


def hash_tree(run_dir: Path) -> dict[str, Any]:
    skip = {"hashes.sha256"}
    lines: list[str] = []
    files = 0
    bytes_ = 0
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(run_dir)
        if rel.name in skip or rel.as_posix() == "hashes.sha256":
            continue
        digest = sha256_file(path)
        size = path.stat().st_size
        lines.append(f"{digest}  {size}  {rel.as_posix()}")
        files += 1
        bytes_ += size
    (run_dir / "hashes.sha256").write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    custody = {
        "tool": "fc-preserve",
        "version": TOOL_VERSION,
        "captured_at": utcnow(),
        "host": os.uname().nodename if hasattr(os, "uname") else "",
        "files": files,
        "bytes": bytes_,
        "algorithm": "sha256",
        "hashes": str(run_dir / "hashes.sha256"),
    }
    write_json(run_dir / "chain-of-custody.json", custody)
    return custody


# ── linux gate ─────────────────────────────────────────────────────────────


def evaluate_gate(cfg: dict[str, Any], run_dir: Path, alias: str) -> dict[str, Any]:
    meta = device_meta(cfg, alias)
    flavor_id = meta.get("linux_flavor")
    flavors = cfg.get("linux_flavors") or {}
    flavor = flavors.get(flavor_id) if flavor_id else None
    extract = {}
    idx = run_dir / "extract" / "index.json"
    if idx.exists():
        extract = json.loads(idx.read_text(encoding="utf-8"))
    custody = run_dir / "chain-of-custody.json"
    catalog = run_dir / "catalog" / "apps.json"
    device_json = run_dir / "device.json"
    checks: list[dict[str, Any]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    check("device.json", device_json.exists(), str(device_json))
    check("extract/index.json", idx.exists())
    check("catalog/apps.json", catalog.exists())
    check("chain-of-custody.json", custody.exists())
    hashes = run_dir / "hashes.sha256"
    check("hashes.sha256", hashes.exists() and hashes.stat().st_size > 0)

    backup_bytes = 0
    backup = run_dir / "backup"
    if backup.exists():
        for p in backup.rglob("*"):
            if p.is_file():
                backup_bytes += p.stat().st_size
    min_b = int((cfg.get("gate") or {}).get("min_backup_bytes") or 1024)
    check("backup size", backup_bytes >= min_b, f"{backup_bytes} bytes")

    required = set((cfg.get("gate") or {}).get("required_extract_ids") or [])
    present = set()
    domains = extract.get("domains") or {}
    for did, spec in domains.items():
        if spec.get("ok"):
            present.add(did)
    if extract.get("info"):
        present.add("identity")
    if (run_dir / "extract" / "Manifest.db").exists() or (run_dir / "extract" / "getprop.txt").exists():
        present.add("manifest")
        present.add("identity")
    if (run_dir / "catalog" / "apps.json").exists():
        present.add("packages")
    missing_req = sorted(r for r in required if r not in present and r not in (extract.get("missing") or []))
    # Required ids that are allowed to be missing if the platform doesn't have them
    platform = extract.get("platform") or (json.loads(device_json.read_text()) if device_json.exists() else {}).get("platform")
    ios_only = {"messages", "contacts", "photos", "manifest"}
    android_only = {"packages"}
    if platform == "android":
        missing_req = [m for m in missing_req if m not in ios_only]
    if platform == "ios":
        missing_req = [m for m in missing_req if m not in android_only]
    # still required if listed and not present
    really_missing = []
    for rid in required:
        if platform == "ios" and rid in android_only:
            continue
        if platform == "android" and rid in ios_only:
            continue
        if rid not in present:
            really_missing.append(rid)
    check("required domains", not really_missing, ",".join(really_missing) or "all present")

    if extract.get("encrypted"):
        check("unencrypted or decrypted backup", False, "encrypted Manifest.db — content incomplete")

    ready = all(c["ok"] for c in checks)
    gate = {
        "alias": alias,
        "ready": ready,
        "checked_at": utcnow(),
        "linux_flavor": flavor,
        "wipe_warning": bool(flavor and flavor.get("wipe")),
        "checks": checks,
        "refuse_reason": None if ready else "preservation incomplete — do not flash",
        "next": (
            f"Device {alias} is preserved. You may flash {flavor.get('name') if flavor else 'your linux flavor'}."
            if ready
            else "Plug the phone in if needed, then: fcs preserve all GrokBotBaby"
        ),
    }
    write_json(run_dir / "linux-gate.json", gate)
    return gate


# ── commands ───────────────────────────────────────────────────────────────


def cmd_probe(_args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    result = probe_all()
    print(json.dumps(result, indent=2, default=str))
    if result["count"] == 0:
        print("\nno phone on USB. unlock GrokBotBaby, tap Trust, then retry.", file=sys.stderr)
        print("ios:  brew install libimobiledevice && idevice_id -l", file=sys.stderr)
        print("android: enable USB debugging, then adb devices", file=sys.stderr)
        return 2
    return 0


def cmd_devices(_args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    print(json.dumps({"default": cfg.get("default_device"), "devices": cfg.get("devices")}, indent=2))
    return 0


def bind_and_backup(args: argparse.Namespace, cfg: dict[str, Any]) -> tuple[int, Path | None]:
    alias = resolve_alias(cfg, args.device)
    meta = device_meta(cfg, alias)
    probe = probe_all()
    want = meta.get("expected_platform") or "auto"
    if want == "auto":
        want = None
    device = pick_device(probe, want)
    if not device:
        print(json.dumps({"ok": False, "error": "no USB device", "probe": probe}, indent=2, default=str))
        return 2, None
    run_dir = new_run_dir(cfg, alias)
    write_json(run_dir / "probe.json", probe)
    write_json(
        run_dir / "device.json",
        {
            "alias": alias,
            "meta": meta,
            "attached": device,
            "captured_at": utcnow(),
            "tool": {"name": "fc-preserve", "version": TOOL_VERSION},
        },
    )
    preserve = meta.get("preserve") or {}
    if device["platform"] == "ios":
        result = backup_ios(device, run_dir, encrypted=bool(preserve.get("encrypted_ios", True)))
    else:
        result = backup_android(device, run_dir, include_sdcard=bool(preserve.get("include_sdcard", True)))
    write_json(run_dir / "backup-result.json", result)
    print(json.dumps({"alias": alias, "run": str(run_dir), "backup": result}, indent=2, default=str))
    return (0 if result.get("ok") else 1), run_dir


def cmd_backup(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    code, _ = bind_and_backup(args, cfg)
    return code


def run_extract(cfg: dict[str, Any], run_dir: Path) -> dict[str, Any]:
    device = json.loads((run_dir / "device.json").read_text(encoding="utf-8"))
    platform = (device.get("attached") or {}).get("platform")
    backup = run_dir / "backup"
    extract_dir = run_dir / "extract"
    if platform == "ios":
        root = find_ios_backup_root(backup)
        if not root:
            report = {"ok": False, "error": "no iOS backup found", "path": str(backup)}
            write_json(extract_dir / "index.json", report)
            return report
        return extract_ios(root, extract_dir, cfg)
    return extract_android(backup, extract_dir)


def cmd_extract(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir:
        print("no preservation run found. fcs preserve backup GrokBotBaby", file=sys.stderr)
        return 2
    report = run_extract(cfg, run_dir)
    print(json.dumps({"run": str(run_dir), "extract": report}, indent=2, default=str))
    return 0 if not report.get("error") else 1


def cmd_catalog(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir:
        print("no run", file=sys.stderr)
        return 2
    device = None
    dj = run_dir / "device.json"
    if dj.exists():
        device = json.loads(dj.read_text(encoding="utf-8")).get("attached")
    catalog = build_catalog(run_dir, alias, device)
    print(json.dumps({"run": str(run_dir), "count": catalog["count"], "path": str(run_dir / "catalog" / "apps.json")}, indent=2))
    return 0


def cmd_osint(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir or not (run_dir / "device.json").exists():
        print("no run", file=sys.stderr)
        return 2
    device_doc = json.loads((run_dir / "device.json").read_text(encoding="utf-8"))
    extract = {}
    idx = run_dir / "extract" / "index.json"
    if idx.exists():
        extract = json.loads(idx.read_text(encoding="utf-8"))
    inv = build_osint(run_dir, alias, device_doc.get("attached") or {}, extract)
    print(json.dumps(inv, indent=2, default=str))
    return 0


def cmd_hash(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir:
        print("no run", file=sys.stderr)
        return 2
    custody = hash_tree(run_dir)
    print(json.dumps(custody, indent=2))
    return 0


def cmd_gate(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir:
        print("no run", file=sys.stderr)
        return 2
    gate = evaluate_gate(cfg, run_dir, alias)
    print(json.dumps(gate, indent=2, default=str))
    return 0 if gate.get("ready") else 3


def cmd_linux(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    alias = resolve_alias(cfg, args.device)
    run_dir = Path(args.run) if args.run else latest_run(cfg, alias)
    if not run_dir:
        print("no run — preserve first", file=sys.stderr)
        return 2
    gate = evaluate_gate(cfg, run_dir, alias)
    if not gate.get("ready"):
        print(json.dumps(gate, indent=2, default=str))
        print("\nREFUSE: do not flash linux until the gate is ready.", file=sys.stderr)
        return 3
    flavor = gate.get("linux_flavor") or {}
    print(
        json.dumps(
            {
                "ready": True,
                "alias": alias,
                "run": str(run_dir),
                "flavor": flavor,
                "wipe": flavor.get("wipe"),
                "url": flavor.get("url"),
                "notes": flavor.get("notes"),
                "reminder": "Flashing wipes the phone. Vault is local and hashed. Keep the vault disk until linux testing is done.",
            },
            indent=2,
        )
    )
    return 0


def cmd_all(args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    code, run_dir = bind_and_backup(args, cfg)
    if not run_dir:
        return code
    extract = run_extract(cfg, run_dir)
    device_doc = json.loads((run_dir / "device.json").read_text(encoding="utf-8"))
    catalog = build_catalog(run_dir, resolve_alias(cfg, args.device), device_doc.get("attached"))
    osint = build_osint(run_dir, resolve_alias(cfg, args.device), device_doc.get("attached") or {}, extract)
    custody = hash_tree(run_dir)
    gate = evaluate_gate(cfg, run_dir, resolve_alias(cfg, args.device))
    summary = {
        "run": str(run_dir),
        "backup_ok": code == 0,
        "extract_missing": extract.get("missing"),
        "apps": catalog.get("count"),
        "osint_warnings": osint.get("warnings"),
        "files_hashed": custody.get("files"),
        "bytes": custody.get("bytes"),
        "linux_gate": gate,
    }
    write_json(run_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, default=str))
    if code != 0:
        return code
    return 0 if gate.get("ready") else 3


def cmd_doctor(_args: argparse.Namespace, cfg: dict[str, Any]) -> int:
    tools = {
        "python": sys.executable,
        "idevice_id": which("idevice_id"),
        "ideviceinfo": which("ideviceinfo"),
        "idevicebackup2": which("idevicebackup2"),
        "adb": which("adb"),
        "pymobiledevice3": which("pymobiledevice3"),
    }
    vault = vault_root(cfg)
    print(
        json.dumps(
            {
                "tool": TOOL_VERSION,
                "config": str(DEFAULT_CONFIG),
                "vault": str(vault),
                "vault_exists": vault.exists(),
                "default_device": cfg.get("default_device"),
                "tools": tools,
                "ios_ready": bool(tools["idevicebackup2"] and tools["ideviceinfo"]),
                "android_ready": bool(tools["adb"]),
            },
            indent=2,
        )
    )
    if not tools["idevicebackup2"] and not tools["adb"]:
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="fc-preserve", description="Device backup / OSINT / linux-flash gate")
    p.add_argument("--config", type=Path, default=None)
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_dev(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("device", nargs="?", default=None, help="alias (default GrokBotBaby)")
        sp.add_argument("--run", default=None, help="existing run directory")

    for name, fn, help_ in (
        ("probe", cmd_probe, "list USB iOS + Android devices"),
        ("devices", cmd_devices, "print alias registry"),
        ("doctor", cmd_doctor, "check host tools + vault"),
        ("backup", cmd_backup, "full local backup of attached phone"),
        ("extract", cmd_extract, "parse backup into messages/photos/apps"),
        ("catalog", cmd_catalog, "IntuneBrew-style app formulas"),
        ("osint", cmd_osint, "identity inventory"),
        ("hash", cmd_hash, "SHA-256 chain of custody"),
        ("gate", cmd_gate, "linux-install readiness"),
        ("linux", cmd_linux, "print flash notes only if gate is ready"),
        ("all", cmd_all, "backup + extract + catalog + hash + gate"),
    ):
        sp = sub.add_parser(name, help=help_)
        if name not in ("probe", "devices", "doctor"):
            add_dev(sp)
        sp.set_defaults(func=fn)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = load_config(args.config)
    return int(args.func(args, cfg))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        raise SystemExit(130)
