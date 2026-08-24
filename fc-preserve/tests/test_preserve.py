#!/usr/bin/env python3
"""Synthetic-vault tests for fc-preserve (no phone required)."""
from __future__ import annotations

import json
import plistlib
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import preserve as P  # noqa: E402


def _write_ios_backup(root: Path) -> Path:
    backup = root / "backup" / "UDID"
    (backup / "ab").mkdir(parents=True)
    info = {
        "Device Name": "GrokBotBaby",
        "Product Type": "iPhone14,5",
        "Product Version": "18.5",
        "Serial Number": "TESTSERIAL",
        "Unique Identifier": "UDID",
    }
    with (backup / "Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    with (backup / "Manifest.plist").open("wb") as f:
        plistlib.dump({"IsEncrypted": False, "Applications": {"com.example.app": {}}}, f)

    db = backup / "Manifest.db"
    conn = sqlite3.connect(db)
    conn.execute(
        "CREATE TABLE Files (fileID TEXT, domain TEXT, relativePath TEXT, flags INTEGER, file BLOB)"
    )
    sms = b"not-a-real-sms-db-but-present"
    sms_id = "a" * 40
    (backup / sms_id[:2]).mkdir(exist_ok=True)
    (backup / sms_id[:2] / sms_id).write_bytes(sms)
    conn.execute(
        "INSERT INTO Files VALUES (?,?,?,?,?)",
        (sms_id, "HomeDomain", "Library/SMS/sms.db", 1, None),
    )
    contacts_id = "d" * 40
    (backup / contacts_id[:2]).mkdir(exist_ok=True)
    (backup / contacts_id[:2] / contacts_id).write_bytes(b"contacts-placeholder")
    conn.execute(
        "INSERT INTO Files VALUES (?,?,?,?,?)",
        (contacts_id, "HomeDomain", "Library/AddressBook/AddressBook.sqlitedb", 1, None),
    )
    photo_id = "b" * 40
    (backup / photo_id[:2]).mkdir(exist_ok=True)
    (backup / photo_id[:2] / photo_id).write_bytes(b"\xff\xd8fakejpeg")
    conn.execute(
        "INSERT INTO Files VALUES (?,?,?,?,?)",
        (photo_id, "CameraRollDomain", "Media/DCIM/100APPLE/IMG_0001.JPG", 1, None),
    )
    conn.execute(
        "INSERT INTO Files VALUES (?,?,?,?,?)",
        ("c" * 40, "AppDomain-com.example.app", "Documents/note.txt", 1, None),
    )
    conn.commit()
    conn.close()
    return backup


class PreserveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="fc-preserve-"))
        self.cfg = P.load_config()
        self.cfg["vault_root"] = str(self.tmp / "vault")

    def test_alias_grokbotbaby(self) -> None:
        self.assertEqual(P.resolve_alias(self.cfg, "baby"), "GrokBotBaby")
        self.assertEqual(P.resolve_alias(self.cfg, "gbb"), "GrokBotBaby")
        self.assertEqual(P.resolve_alias(self.cfg, None), "GrokBotBaby")

    def test_ios_extract_and_catalog_and_gate(self) -> None:
        run_dir = self.tmp / "GrokBotBaby" / "run1"
        for sub in ("backup", "extract", "catalog", "osint", "logs"):
            (run_dir / sub).mkdir(parents=True)
        backup = _write_ios_backup(run_dir)
        P.write_json(
            run_dir / "device.json",
            {
                "alias": "GrokBotBaby",
                "attached": {
                    "platform": "ios",
                    "udid": "UDID",
                    "name": "GrokBotBaby",
                    "model": "iPhone14,5",
                    "os": "18.5",
                    "serial": "TESTSERIAL",
                    "imei": "",
                },
            },
        )
        report = P.extract_ios(backup, run_dir / "extract", self.cfg)
        self.assertIn("photos", report["domains"])
        self.assertTrue(report["domains"]["photos"]["ok"])
        self.assertTrue((run_dir / "extract" / "photos").exists())
        catalog = P.build_catalog(run_dir, "GrokBotBaby", {"platform": "ios"})
        self.assertGreaterEqual(catalog["count"], 1)
        self.assertTrue((run_dir / "catalog" / "Apps" / "com.example.app.json").exists())
        P.build_osint(run_dir, "GrokBotBaby", {"platform": "ios", "udid": "UDID"}, report)
        # seed backup bytes
        (run_dir / "backup" / "pad.bin").write_bytes(b"x" * 2048)
        custody = P.hash_tree(run_dir)
        self.assertGreater(custody["files"], 0)
        gate = P.evaluate_gate(self.cfg, run_dir, "GrokBotBaby")
        self.assertTrue(gate["ready"], gate)

    def test_android_extract(self) -> None:
        run_dir = self.tmp / "GrokBotBaby" / "run-and"
        backup = run_dir / "backup"
        backup.mkdir(parents=True)
        (backup / "packages-all.txt").write_text("package:/data/app/base.apk=com.gbb.bot\n")
        (backup / "getprop.txt").write_text("[ro.product.model]: [Pixel 8]\n")
        (backup / "sdcard").mkdir()
        (backup / "sdcard" / "DCIM").mkdir()
        report = P.extract_android(backup, run_dir / "extract")
        self.assertTrue(report["domains"]["packages"]["ok"])
        catalog = P.build_catalog(run_dir, "GrokBotBaby", {"platform": "android"})
        self.assertEqual(catalog["apps"][0]["bundleId"], "com.gbb.bot")

    def test_gate_refuses_empty(self) -> None:
        run_dir = self.tmp / "empty"
        run_dir.mkdir()
        gate = P.evaluate_gate(self.cfg, run_dir, "GrokBotBaby")
        self.assertFalse(gate["ready"])
        self.assertIn("do not flash", gate["refuse_reason"])


if __name__ == "__main__":
    unittest.main()
