use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::node::Snapshot;

pub const DEFAULT_VAULT: &str = "/Volumes/MacBookPro - Data/FC-Preserve";
pub const BABY_UDID: &str = "4ea7e05b3045f0e9036275125a85225dd6dd9bb9";
pub const SNAPSHOT_NAME: &str = "fc-preserve-tree.json";
pub const SESSION_NAME: &str = "fc-preserve-session.json";
pub const SEAT_NAME: &str = "fc-preserve-seat.json";

pub fn home_dir() -> PathBuf {
    env::var_os("HOME")
        .or_else(|| env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

pub fn hotpipe_dir() -> PathBuf {
    env::var_os("FC_PRESERVE_HOTPIPE")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".grok/pool/hotpipe"))
}

pub fn vault_root() -> PathBuf {
    env::var_os("FC_PRESERVE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_VAULT))
}

pub fn images_dir() -> PathBuf {
    vault_root().join("images")
}

pub fn snapshot_path() -> PathBuf {
    hotpipe_dir().join(SNAPSHOT_NAME)
}

pub fn hf_hub_dir() -> PathBuf {
    home_dir().join(".cache/huggingface/hub")
}

pub fn lmstudio_models_dir() -> PathBuf {
    home_dir().join(".lmstudio/models")
}

pub fn hostname() -> String {
    if let Ok(h) = env::var("FC_PRESERVE_HOST") {
        if !h.is_empty() {
            return h;
        }
    }
    if let Ok(out) = Command::new("hostname").output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return s;
            }
        }
    }
    "unknown-host".into()
}

/// UTC RFC3339 without a chrono/time crate.
pub fn utc_now() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (y, mo, d, h, mi, s) = civil_utc(secs);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

fn civil_utc(secs: u64) -> (i32, u32, u32, u32, u32, u32) {
    let z = secs / 86400;
    let rem = secs % 86400;
    let h = (rem / 3600) as u32;
    let mi = ((rem % 3600) / 60) as u32;
    let s = (rem % 60) as u32;
    // Howard Hinnant civil-from-days, days since 1970-01-01
    let z = z as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let mo = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32;
    let y = (y + if mo <= 2 { 1 } else { 0 }) as i32;
    (y, mo, d, h, mi, s)
}

pub fn run_cmd(bin: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(bin).args(args).output().ok()?;
    if !out.status.success() && out.stdout.is_empty() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn which(bin: &str) -> bool {
    env::var_os("PATH")
        .map(|p| env::split_paths(&p).any(|d| d.join(bin).is_file()))
        .unwrap_or(false)
}

pub fn write_snapshot_atomic(path: &Path, snap: &Snapshot) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("json.tmp");
    let body = serde_json::to_vec_pretty(snap).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(&body)?;
        f.write_all(b"\n")?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)?;
    Ok(())
}

pub fn load_snapshot(path: &Path) -> io::Result<Snapshot> {
    let data = fs::read(path)?;
    serde_json::from_slice(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

pub fn load_selected(hotpipe: &Path) -> Vec<String> {
    for name in [SESSION_NAME, SEAT_NAME] {
        let p = hotpipe.join(name);
        if let Ok(data) = fs::read(&p) {
            if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&data) {
                if let Some(arr) = v.get("selected").and_then(|x| x.as_array()) {
                    let ids: Vec<String> = arr
                        .iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect();
                    if !ids.is_empty() {
                        return ids;
                    }
                }
            }
        }
    }
    Vec::new()
}

pub fn file_len(path: &Path) -> Option<u64> {
    fs::metadata(path).ok().filter(|m| m.is_file()).map(|m| m.len())
}

pub fn path_exists(path: &Path) -> bool {
    path.exists()
}
