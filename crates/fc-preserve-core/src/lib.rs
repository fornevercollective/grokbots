//! Cross-platform FC-Preserve walker + sitter.
//!
//! No AppKit. std + serde + optional `notify`. The snapshot JSON is the
//! Vision-menu contract: other machines load
//! `~/.grok/pool/hotpipe/fc-preserve-tree.json`.

pub mod kinds;
pub mod node;
pub mod paths;
pub mod sit;
pub mod walk;

pub use kinds::{flashable_for, group_catalog, Kind};
pub use node::{Group, Node, Snapshot, TREE_SCHEMA};
pub use paths::{
    hotpipe_dir, load_snapshot, snapshot_path, vault_root, write_snapshot_atomic, DEFAULT_VAULT,
};
pub use sit::{sit_loop, sit_loop_until, sit_once};
pub use walk::{parse_df, walk_snapshot, walk_with, WalkConfig};

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn tmp() -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "fc-preserve-core-test-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn kinds_roundtrip() {
        for k in [
            Kind::Phone,
            Kind::Desktop,
            Kind::Storage,
            Kind::Radio,
            Kind::Hub,
            Kind::Iot,
            Kind::Camera,
            Kind::Iso,
            Kind::Model,
            Kind::File,
        ] {
            let s = serde_json::to_string(&k).unwrap();
            assert_eq!(s, format!("\"{}\"", k.as_str()));
            let back: Kind = serde_json::from_str(&s).unwrap();
            assert_eq!(back, k);
        }
    }

    #[test]
    fn flashable_never_brick_phone_internal_vault() {
        assert!(!flashable_for("brick", Kind::Phone, ""));
        assert!(!flashable_for("baby", Kind::Phone, BABY));
        assert!(!flashable_for("internal", Kind::Storage, "/"));
        assert!(!flashable_for("vault", Kind::Storage, "/Volumes/MacBookPro - Data"));
        assert!(!flashable_for("qbitos", Kind::Storage, "/Volumes/qbitOS"));
        assert!(!flashable_for("mini", Kind::Desktop, "/"));
        assert!(!flashable_for("iso", Kind::Iso, "/Volumes/MacBookPro - Data/FC-Preserve/images"));
        assert!(flashable_for(
            "iso-foo.iso",
            Kind::Iso,
            "/Volumes/MacBookPro - Data/FC-Preserve/images/foo.iso"
        ));
        assert!(flashable_for("vol-USB", Kind::Storage, "/Volumes/KINGSTON"));
    }

    const BABY: &str = "4ea7e05b3045f0e9036275125a85225dd6dd9bb9";

    #[test]
    fn groups_match_appkit_row() {
        let g = group_catalog();
        let titles: Vec<_> = g.iter().map(|(t, _)| *t).collect();
        assert_eq!(
            titles,
            ["Phones", "Computers", "Storage", "Radios", "Hubs", "IoT", "Images/Models"]
        );
        assert!(g[0].1.contains(&"baby") && g[0].1.contains(&"brick"));
    }

    #[test]
    fn empty_node_is_honest() {
        let n = Node::empty("brick", Kind::Phone, "Brick", "");
        assert_eq!(n.used, None);
        assert_eq!(n.free, None);
        assert!(n.kids.is_empty());
        assert!(!n.flashable);
        assert!(!n.selected);
    }

    #[test]
    fn snapshot_json_keys() {
        let dir = tmp();
        let snap_path = dir.join("fc-preserve-tree.json");
        let cfg = WalkConfig {
            host: "testhost".into(),
            vault: dir.join("vault"),
            hotpipe: dir.join("hotpipe"),
            images: dir.join("vault/images"),
            hf_hub: dir.join("hf"),
            lmstudio: dir.join("lms"),
            snapshot_path: snap_path.clone(),
            selected: vec!["baby".into()],
            source: "walk".into(),
        };
        fs::create_dir_all(&cfg.vault).unwrap();
        fs::create_dir_all(&cfg.hotpipe).unwrap();
        fs::create_dir_all(&cfg.images).unwrap();
        let snap = walk_with(&cfg);
        write_snapshot_atomic(&snap_path, &snap).unwrap();
        let v: serde_json::Value = serde_json::from_str(&fs::read_to_string(&snap_path).unwrap()).unwrap();
        for k in ["schema", "generated_at", "host", "source", "snapshot_path", "groups", "nodes"] {
            assert!(v.get(k).is_some(), "missing snapshot key {k}");
        }
        assert_eq!(v["schema"], TREE_SCHEMA);
        assert_eq!(v["host"], "testhost");
        let node = &v["nodes"][0];
        for k in ["id", "kind", "name", "path", "used", "free", "kids", "selected", "flashable"] {
            assert!(node.get(k).is_some(), "missing node key {k}");
        }
        let baby = snap.node("baby").unwrap();
        assert!(baby.selected);
        assert!(!baby.flashable);
        let brick = snap.node("brick").unwrap();
        assert_eq!(brick.used, None);
        assert_eq!(brick.free, None);
        assert!(!brick.flashable);
        let vault = snap.node("vault").unwrap();
        assert!(!vault.flashable);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_vault_is_empty_not_fake() {
        let dir = tmp();
        let cfg = WalkConfig {
            host: "ghost".into(),
            vault: dir.join("no-such-vault"),
            hotpipe: dir.join("no-hotpipe"),
            images: dir.join("no-images"),
            hf_hub: dir.join("no-hf"),
            lmstudio: dir.join("no-lms"),
            snapshot_path: dir.join("tree.json"),
            selected: vec![],
            source: "walk".into(),
        };
        let snap = walk_with(&cfg);
        let vault = snap.node("vault").unwrap();
        // volume may also be missing — do not invent used/free
        if !std::path::Path::new("/Volumes/MacBookPro - Data").exists() {
            assert_eq!(vault.used, None);
            assert_eq!(vault.free, None);
        }
        assert!(vault.kids.is_empty());
        let iso = snap.node("iso").unwrap();
        assert!(iso.kids.is_empty());
        let models = snap.node("models").unwrap();
        assert!(models.kids.is_empty());
        let _ = fs::remove_dir_all(&dir);
    }
}
