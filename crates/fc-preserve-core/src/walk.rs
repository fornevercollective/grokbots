use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use crate::kinds::{flashable_for, group_catalog, Kind};
use crate::node::{Group, Node, Snapshot, TREE_SCHEMA};
use crate::paths::{
    file_len, hf_hub_dir, hostname, hotpipe_dir, images_dir, load_selected, lmstudio_models_dir,
    run_cmd, snapshot_path, utc_now, vault_root, which, BABY_UDID,
};

#[derive(Debug, Clone)]
pub struct WalkConfig {
    pub host: String,
    pub vault: PathBuf,
    pub hotpipe: PathBuf,
    pub images: PathBuf,
    pub hf_hub: PathBuf,
    pub lmstudio: PathBuf,
    pub snapshot_path: PathBuf,
    pub selected: Vec<String>,
    pub source: String,
}

impl Default for WalkConfig {
    fn default() -> Self {
        let hotpipe = hotpipe_dir();
        let selected = load_selected(&hotpipe);
        Self {
            host: hostname(),
            vault: vault_root(),
            hotpipe: hotpipe.clone(),
            images: images_dir(),
            hf_hub: hf_hub_dir(),
            lmstudio: lmstudio_models_dir(),
            snapshot_path: snapshot_path(),
            selected,
            source: "walk".into(),
        }
    }
}

impl WalkConfig {
    fn is_selected(&self, id: &str) -> bool {
        self.selected.iter().any(|s| s == id)
    }

    fn node(&self, id: &str, kind: Kind, name: &str, path: &str) -> Node {
        Node::empty(id, kind, name, path).with_selected(self.is_selected(id))
    }
}

#[derive(Debug, Clone)]
pub struct Mount {
    pub mount: String,
    pub used: u64,
    pub free: u64,
}

/// Walk the device/vault/host tree. Missing things stay as honest empty nodes
/// (`used`/`free` null, `kids` empty). No guessed phone or IoT sizes.
pub fn walk_snapshot() -> Snapshot {
    walk_with(&WalkConfig::default())
}

pub fn walk_with(cfg: &WalkConfig) -> Snapshot {
    let mounts = parse_df(&run_cmd("df", &["-kP"]).unwrap_or_default());
    let mux = probe_mux();
    let machines = load_json(&cfg.hotpipe.join("machines.json"));
    let cams = load_json(&cfg.hotpipe.join("cams.json"));

    let mut nodes = Vec::new();
    nodes.push(phone_baby(cfg, &mux));
    nodes.push(phone_brick(cfg, &mux));
    nodes.push(desktop_mini(cfg));
    nodes.push(desktop_mbp(cfg, &machines));
    nodes.push(storage_named(cfg, "internal", "Internal", "/", &mounts));
    nodes.push(storage_named(cfg, "mbpvol", "MBP vol", "/Volumes/MacBookPro", &mounts));
    nodes.push(storage_vault(cfg, &mounts));
    nodes.push(storage_named(cfg, "qbitos", "qbitOS", "/Volumes/qbitOS", &mounts));
    nodes.push(storage_usbphone(cfg, &mounts));

    let mut extra_ids = Vec::new();
    for extra in extra_volumes(&mounts) {
        extra_ids.push(extra.id.clone());
        nodes.push(extra);
    }

    nodes.push(radio(cfg, "wifi", "Wi-Fi", &iface_path("en1")));
    nodes.push(radio(cfg, "ble", "BLE", ""));
    nodes.push(radio(cfg, "nfc", "NFC", ""));
    nodes.push(hub(cfg, "usbhub", "USB hub", ""));
    nodes.push(hub(cfg, "qm2", "Qm-2", &iface_path("en8")));
    nodes.push(hub(cfg, "bridge", "Bridge", ""));
    nodes.push(camera(cfg, "kinect", "Kinect", &cams));
    nodes.push(camera(cfg, "nestcam", "Nest cam", &cams));
    nodes.push(iot(cfg, "nest1", "Nest 1"));
    nodes.push(iot(cfg, "nest2", "Nest 2"));
    nodes.push(iot(cfg, "yale1", "Yale 1"));
    nodes.push(iot(cfg, "yale2", "Yale 2"));
    nodes.push(iot(cfg, "tv", "TV"));
    nodes.push(iot(cfg, "console", "Console"));
    nodes.push(iso_library(cfg));
    nodes.push(os_images(cfg));
    nodes.push(models_node(cfg));

    let mut groups: Vec<Group> = group_catalog()
        .into_iter()
        .map(|(title, ids)| Group {
            title: title.to_string(),
            ids: ids.iter().map(|s| (*s).to_string()).collect(),
        })
        .collect();
    if let Some(storage) = groups.iter_mut().find(|g| g.title == "Storage") {
        storage.ids.extend(extra_ids);
    }

    Snapshot {
        schema: TREE_SCHEMA.to_string(),
        generated_at: utc_now(),
        host: cfg.host.clone(),
        source: cfg.source.clone(),
        snapshot_path: cfg.snapshot_path.display().to_string(),
        groups,
        nodes,
    }
}

fn phone_baby(cfg: &WalkConfig, mux: &Mux) -> Node {
    let mut n = cfg.node("baby", Kind::Phone, "GrokBotBaby", "");
    if let Some(dev) = mux.ios.iter().find(|d| d.udid == BABY_UDID) {
        n.path = dev.udid.clone();
        n.used = dev.used;
        n.free = dev.free;
        if let Some(name) = &dev.name {
            n.name = name.clone();
        }
    }
    // mux empty → stay empty. Do not guess iPhone capacity.
    n.flashable = false;
    n
}

fn phone_brick(cfg: &WalkConfig, mux: &Mux) -> Node {
    let mut n = cfg.node("brick", Kind::Phone, "Brick", "");
    if let Some(dev) = mux
        .ios
        .iter()
        .find(|d| d.udid != BABY_UDID)
    {
        n.path = dev.udid.clone();
        n.used = dev.used;
        n.free = dev.free;
        if let Some(name) = &dev.name {
            if n.name == "Brick" {
                n.name = format!("Brick ({name})");
            }
        }
    }
    n.flashable = false;
    n
}

fn desktop_mini(cfg: &WalkConfig) -> Node {
    let this_mini = cfg.host.to_ascii_lowercase().contains("mini");
    let path = if this_mini { "/" } else { "" };
    let mut n = cfg.node("mini", Kind::Desktop, "Mini", path);
    if this_mini {
        n.name = cfg.host.clone();
        let mut kids = Vec::new();
        kids.push(hotpipe_node(cfg));
        n.kids = kids;
    }
    n.flashable = false;
    n
}

fn desktop_mbp(cfg: &WalkConfig, machines: &Option<serde_json::Value>) -> Node {
    let mut n = cfg.node("mbp2019", Kind::Desktop, "2019 MBP", "");
    if let Some(v) = machines {
        if let Some(hosts) = v.get("hosts").and_then(|h| h.as_array()) {
            if let Some(h) = hosts.iter().find(|h| h.get("id").and_then(|x| x.as_str()) == Some("grokpool-laptop")) {
                let via = h.get("via").and_then(|x| x.as_str()).unwrap_or("");
                n.path = via.to_string();
                // no used/free — peer disk size is unknown unless the peer sits
            }
        }
    }
    n.flashable = false;
    n
}

fn storage_named(cfg: &WalkConfig, id: &str, name: &str, path: &str, mounts: &BTreeMap<String, Mount>) -> Node {
    let mut n = cfg.node(id, Kind::Storage, name, path);
    if let Some(m) = mounts.get(path) {
        n.used = Some(m.used);
        n.free = Some(m.free);
    } else if !Path::new(path).exists() {
        n.path = path.to_string();
        n.used = None;
        n.free = None;
    }
    n.flashable = flashable_for(id, Kind::Storage, path);
    n
}

fn storage_vault(cfg: &WalkConfig, mounts: &BTreeMap<String, Mount>) -> Node {
    let vol = "/Volumes/MacBookPro - Data";
    let mut n = cfg.node("vault", Kind::Storage, "Vault", vol);
    if let Some(m) = mounts.get(vol) {
        n.used = Some(m.used);
        n.free = Some(m.free);
    } else if let Some(m) = mounts.get(&cfg.vault.display().to_string()) {
        n.path = cfg.vault.display().to_string();
        n.used = Some(m.used);
        n.free = Some(m.free);
    }
    let mut kids = Vec::new();
    let root = &cfg.vault;
    if root.is_dir() {
        kids.push(
            cfg.node("vault-root", Kind::File, "FC-Preserve", &root.display().to_string()),
        );
        if let Ok(rd) = fs::read_dir(root) {
            let mut names: Vec<_> = rd.filter_map(|e| e.ok()).collect();
            names.sort_by_key(|e| e.file_name());
            for e in names {
                let name = e.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') {
                    continue;
                }
                let p = e.path();
                let id = format!("vault-{name}");
                if p.is_file() {
                    kids.push(
                        cfg.node(&id, Kind::File, &name, &p.display().to_string())
                            .with_space(file_len(&p), None),
                    );
                } else if p.is_dir() {
                    kids.push(cfg.node(&id, Kind::File, &name, &p.display().to_string()));
                }
            }
        }
    }
    n.kids = kids;
    n.flashable = false;
    n
}

fn storage_usbphone(cfg: &WalkConfig, mounts: &BTreeMap<String, Mount>) -> Node {
    let mut n = cfg.node("usbphone", Kind::Storage, "USB phone", "");
    if let Some((_, m)) = mounts.iter().find(|(mnt, _)| {
        let l = mnt.to_ascii_lowercase();
        l.contains("iphone") || l.contains("dcim") || l.contains("android")
    }) {
        n.path = m.mount.clone();
        n.used = Some(m.used);
        n.free = Some(m.free);
    }
    n.flashable = false;
    n
}

fn extra_volumes(mounts: &BTreeMap<String, Mount>) -> Vec<Node> {
    let known: HashSet<&str> = [
        "/",
        "/Volumes/MacBookPro",
        "/Volumes/MacBookPro - Data",
        "/Volumes/qbitOS",
        "/Volumes/Macintosh HD",
    ]
    .into_iter()
    .collect();
    let mut out = Vec::new();
    for (mnt, m) in mounts {
        if known.contains(mnt.as_str()) {
            continue;
        }
        let l = mnt.to_ascii_lowercase();
        if l.contains("iphone") || l.contains("dcim") || l.contains("android") {
            continue;
        }
        if skip_mount(mnt) {
            continue;
        }
        let name = Path::new(mnt)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or(mnt)
            .to_string();
        let id = format!("vol-{name}");
        let flashable = flashable_for(&id, Kind::Storage, mnt);
        out.push(
            Node::empty(id, Kind::Storage, name, mnt.clone())
                .with_space(Some(m.used), Some(m.free))
                .with_selected(false),
        );
        let _ = flashable;
    }
    out
}

fn skip_mount(mnt: &str) -> bool {
    mnt == "/dev"
        || mnt.starts_with("/System/Volumes")
        || mnt.starts_with("/proc")
        || mnt.starts_with("/sys")
        || mnt.starts_with("/run/user")
        || mnt == "/boot/efi"
        || mnt.contains("/Preboot")
}

fn radio(cfg: &WalkConfig, id: &str, name: &str, path: &str) -> Node {
    let mut n = cfg.node(id, Kind::Radio, name, path);
    n.flashable = false;
    n
}

fn hub(cfg: &WalkConfig, id: &str, name: &str, path: &str) -> Node {
    let mut n = cfg.node(id, Kind::Hub, name, path);
    n.flashable = false;
    n
}

fn camera(cfg: &WalkConfig, id: &str, name: &str, cams: &Option<serde_json::Value>) -> Node {
    let mut n = cfg.node(id, Kind::Camera, name, "");
    n.flashable = false;
    if id == "kinect" {
        if let Some(v) = cams {
            if let Some(k) = v.get("kinect") {
                let live = k
                    .get("kinect")
                    .and_then(|x| x.get("camera"))
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false);
                if !live {
                    // stay empty — USB dark is not a size
                    n.used = None;
                    n.free = None;
                }
            }
        }
    }
    n
}

fn iot(cfg: &WalkConfig, id: &str, name: &str) -> Node {
    cfg.node(id, Kind::Iot, name, "")
}

fn iso_library(cfg: &WalkConfig) -> Node {
    let mut n = cfg.node("iso", Kind::Iso, "ISO", &cfg.images.display().to_string());
    let mut kids = Vec::new();
    if cfg.images.is_dir() {
        if let Ok(rd) = fs::read_dir(&cfg.images) {
            let mut ents: Vec<_> = rd.filter_map(|e| e.ok()).collect();
            ents.sort_by_key(|e| e.file_name());
            for e in ents {
                let p = e.path();
                let name = e.file_name().to_string_lossy().into_owned();
                let low = name.to_ascii_lowercase();
                if low.ends_with(".iso") || low.ends_with(".img") || low.ends_with(".dmg") || low.ends_with(".zip")
                {
                    let id = format!("iso-{name}");
                    let path = p.display().to_string();
                    kids.push(
                        Node::empty(id, Kind::Iso, name, path.clone())
                            .with_space(file_len(&p), None)
                            .with_selected(false),
                    );
                } else if name == "catalog.json" {
                    kids.push(
                        cfg.node("iso-catalog", Kind::File, "catalog.json", &p.display().to_string())
                            .with_space(file_len(&p), None),
                    );
                }
            }
        }
    }
    n.kids = kids;
    n.flashable = false;
    n
}

fn os_images(cfg: &WalkConfig) -> Node {
    let mut n = cfg.node("osimg", Kind::Iso, "OS img", &cfg.images.display().to_string());
    n.flashable = false;
    n
}

fn models_node(cfg: &WalkConfig) -> Node {
    let mut n = cfg.node("models", Kind::Model, "Models", "");
    let mut kids = Vec::new();
    kids.extend(list_models("hf", &cfg.hf_hub, "models--"));
    kids.extend(list_models("lms", &cfg.lmstudio, "models--"));
    if !cfg.hf_hub.as_os_str().is_empty() && cfg.hf_hub.is_dir() && n.path.is_empty() {
        n.path = cfg.hf_hub.display().to_string();
    } else if cfg.lmstudio.is_dir() && n.path.is_empty() {
        n.path = cfg.lmstudio.display().to_string();
    }
    n.kids = kids;
    n.flashable = false;
    n
}

fn list_models(prefix: &str, dir: &Path, needle: &str) -> Vec<Node> {
    let mut kids = Vec::new();
    let Ok(rd) = fs::read_dir(dir) else {
        return kids;
    };
    let mut ents: Vec<_> = rd.filter_map(|e| e.ok()).collect();
    ents.sort_by_key(|e| e.file_name());
    for e in ents {
        let name = e.file_name().to_string_lossy().into_owned();
        if !name.starts_with(needle) && prefix == "hf" {
            continue;
        }
        if name.starts_with('.') {
            continue;
        }
        let pretty = name.replace("models--", "").replace("--", "/");
        let p = e.path();
        // Directory st_size is not content size. Leave used null (honest).
        kids.push(Node::empty(
            format!("{prefix}-{pretty}"),
            Kind::Model,
            pretty,
            p.display().to_string(),
        ));
    }
    kids
}

fn hotpipe_node(cfg: &WalkConfig) -> Node {
    let mut n = cfg.node(
        "hotpipe",
        Kind::File,
        "hotpipe",
        &cfg.hotpipe.display().to_string(),
    );
    let mut kids = Vec::new();
    if cfg.hotpipe.is_dir() {
        if let Ok(rd) = fs::read_dir(&cfg.hotpipe) {
            let mut ents: Vec<_> = rd.filter_map(|e| e.ok()).collect();
            ents.sort_by_key(|e| e.file_name());
            for e in ents {
                let name = e.file_name().to_string_lossy().into_owned();
                if !name.starts_with("fc-preserve-") {
                    continue;
                }
                let p = e.path();
                kids.push(
                    cfg.node(
                        &format!("hotpipe-{name}"),
                        Kind::File,
                        &name,
                        &p.display().to_string(),
                    )
                    .with_space(file_len(&p), None),
                );
            }
        }
    }
    n.kids = kids;
    n
}

fn iface_path(name: &str) -> String {
    #[cfg(target_os = "macos")]
    {
        name.to_string()
    }
    #[cfg(not(target_os = "macos"))]
    {
        let p = format!("/sys/class/net/{name}");
        if Path::new(&p).exists() {
            p
        } else {
            String::new()
        }
    }
}

#[derive(Debug, Default)]
struct Mux {
    ios: Vec<IosDev>,
    android: Vec<String>,
}

#[derive(Debug, Clone)]
struct IosDev {
    udid: String,
    name: Option<String>,
    used: Option<u64>,
    free: Option<u64>,
}

fn probe_mux() -> Mux {
    let mut mux = Mux::default();
    if which("idevice_id") {
        if let Some(out) = run_cmd("idevice_id", &["-l"]) {
            for line in out.lines() {
                let udid = line.trim();
                if udid.is_empty() {
                    continue;
                }
                let name = run_cmd("ideviceinfo", &["-u", udid, "-k", "DeviceName"])
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty());
                let total = parse_u64_cmd("ideviceinfo", &["-u", udid, "-k", "TotalDiskCapacity"]);
                let avail = parse_u64_cmd("ideviceinfo", &["-u", udid, "-k", "TotalDataAvailable"]);
                let used = match (total, avail) {
                    (Some(t), Some(a)) if t >= a => Some(t - a),
                    _ => None,
                };
                mux.ios.push(IosDev {
                    udid: udid.to_string(),
                    name,
                    used,
                    free: avail,
                });
            }
        }
    }
    if which("adb") {
        if let Some(out) = run_cmd("adb", &["devices"]) {
            for line in out.lines().skip(1) {
                let mut parts = line.split_whitespace();
                if let (Some(serial), Some(state)) = (parts.next(), parts.next()) {
                    if state == "device" {
                        mux.android.push(serial.to_string());
                    }
                }
            }
        }
    }
    mux
}

fn parse_u64_cmd(bin: &str, args: &[&str]) -> Option<u64> {
    run_cmd(bin, args)?.trim().parse().ok()
}

fn load_json(path: &Path) -> Option<serde_json::Value> {
    let data = fs::read(path).ok()?;
    serde_json::from_slice(&data).ok()
}

/// POSIX `df -kP` parser. Values become bytes. Skips header and junk rows.
/// Parse from the Capacity (`28%`) column so filesystem names with spaces
/// (`map auto_home`) do not shift the mount path.
pub fn parse_df(text: &str) -> BTreeMap<String, Mount> {
    let mut out = BTreeMap::new();
    for (i, line) in text.lines().enumerate() {
        if i == 0 && line.to_ascii_lowercase().contains("filesystem") {
            continue;
        }
        let cols: Vec<&str> = line.split_whitespace().collect();
        let pct = match cols.iter().position(|c| c.ends_with('%')) {
            Some(i) if i >= 3 => i,
            _ => continue,
        };
        let used_k: u64 = match cols[pct - 2].parse() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let free_k: u64 = match cols[pct - 1].parse() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let mount = cols[pct + 1..].join(" ");
        if mount.is_empty() {
            continue;
        }
        out.insert(
            mount.clone(),
            Mount {
                mount,
                used: used_k.saturating_mul(1024),
                free: free_k.saturating_mul(1024),
            },
        );
    }
    out
}

#[cfg(test)]
mod df_tests {
    use super::*;

    #[test]
    fn df_posix_bytes() {
        let text = "\
Filesystem     1024-blocks       Used Available Capacity  Mounted on
/dev/disk3s3s1   239362496   12272836  33114768    28%    /
/dev/disk9s1    1953309744 1707077124 231012452    89%    /Volumes/MacBookPro - Data
";
        let m = parse_df(text);
        assert_eq!(m.get("/").unwrap().used, 12272836 * 1024);
        assert_eq!(
            m.get("/Volumes/MacBookPro - Data").unwrap().free,
            231012452 * 1024
        );
    }

    #[test]
    fn df_spaced_fs_name_does_not_invent_mount() {
        let text = "\
Filesystem     1024-blocks       Used Available Capacity  Mounted on
map auto_home            0          0         0   100%    /System/Volumes/Data/home
/dev/disk7s1     976557744  793885456 182469992    82%    /Volumes/qbitOS
";
        let m = parse_df(text);
        assert!(m.get("/System/Volumes/Data/home").is_some());
        assert!(m.keys().all(|k| !k.starts_with("100%")));
        assert_eq!(m.get("/Volumes/qbitOS").unwrap().used, 793885456 * 1024);
    }
}
