use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;

/// Device/menu kinds for the portable tree. Matches the Vision-menu contract.
/// AppKit may use a few extra paint labels (`laptop`, `image`, `slot`); those
/// map into this set so other machines and a future visionOS menu share one enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Phone,
    Desktop,
    Storage,
    Radio,
    Hub,
    Iot,
    Camera,
    Iso,
    Model,
    File,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Phone => "phone",
            Kind::Desktop => "desktop",
            Kind::Storage => "storage",
            Kind::Radio => "radio",
            Kind::Hub => "hub",
            Kind::Iot => "iot",
            Kind::Camera => "camera",
            Kind::Iso => "iso",
            Kind::Model => "model",
            Kind::File => "file",
        }
    }
}

impl fmt::Display for Kind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Kind {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "phone" => Ok(Kind::Phone),
            "desktop" | "laptop" => Ok(Kind::Desktop),
            "storage" => Ok(Kind::Storage),
            "radio" => Ok(Kind::Radio),
            "hub" => Ok(Kind::Hub),
            "iot" => Ok(Kind::Iot),
            "camera" => Ok(Kind::Camera),
            "iso" | "image" => Ok(Kind::Iso),
            "model" => Ok(Kind::Model),
            "file" | "slot" => Ok(Kind::File),
            other => Err(format!("unknown kind {other}")),
        }
    }
}

/// Flash lock. Brick / any phone / Internal / vault are never flashable.
/// qbitOS, the MacBookPro volume, and USB-phone mounts stay locked too.
/// Default is false — a node is flashable only when it is clearly a
/// removable dest or a disk-image file under the images library.
pub fn flashable_for(id: &str, kind: Kind, path: &str) -> bool {
    match kind {
        Kind::Phone | Kind::Desktop | Kind::Radio | Kind::Hub | Kind::Iot | Kind::Camera => {
            return false;
        }
        Kind::File | Kind::Model => return false,
        Kind::Iso | Kind::Storage => {}
    }

    let id_l = id.to_ascii_lowercase();
    if matches!(
        id_l.as_str(),
        "brick" | "baby" | "internal" | "vault" | "qbitos" | "mbpvol" | "usbphone"
    ) {
        return false;
    }

    let p = path.trim();
    let pl = p.to_ascii_lowercase();
    if p.is_empty() {
        return false;
    }
    if pl == "/" || pl.starts_with("/system") || pl.starts_with("/users/") {
        return false;
    }
    if pl.contains("iphone") || pl.contains("brick") || pl.contains("grokbotbaby") {
        return false;
    }
    if pl == "/volumes/macbookpro - data"
        || (pl.starts_with("/volumes/macbookpro - data/") && !pl.contains("/images/"))
    {
        return false;
    }
    if pl == "/volumes/qbitos" || pl.starts_with("/volumes/qbitos/") {
        return false;
    }
    if pl == "/volumes/macbookpro" || pl.starts_with("/volumes/macbookpro/") {
        return false;
    }

    if kind == Kind::Iso {
        return pl.ends_with(".iso") || pl.ends_with(".img") || pl.ends_with(".dmg");
    }

    // Extra discovered volumes only — catalog storage stays locked above.
    id_l.starts_with("vol-") || id_l.starts_with("usb-")
}

/// AppKit row groups. Titles stay stable so a Vision menu can paint the same row.
pub fn group_catalog() -> Vec<(&'static str, &'static [&'static str])> {
    vec![
        ("Phones", &["baby", "brick"]),
        ("Computers", &["mini", "mbp2019"]),
        ("Storage", &["internal", "mbpvol", "vault", "qbitos", "usbphone"]),
        ("Radios", &["wifi", "ble", "nfc"]),
        ("Hubs", &["usbhub", "qm2", "bridge"]),
        ("IoT", &["kinect", "nestcam", "nest1", "nest2", "yale1", "yale2", "tv", "console"]),
        ("Images/Models", &["iso", "osimg", "models"]),
    ]
}
