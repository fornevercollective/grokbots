use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

use clap::{Parser, Subcommand};
use fc_preserve_core::{
    load_snapshot, sit_loop, sit_once, snapshot_path, walk_snapshot, write_snapshot_atomic,
};

const DEFAULT_DEVICE: &str = "GrokBotBaby";
const KNOWN_REPO: &str = "/Volumes/qbitOS/00.dev/grokbotsGH";
const HOTSPOT_LINE: &str =
    "USB iPhone present, en9 hotspot/NCM up, usbmux empty. turn Personal Hotspot OFF, unlock, Trust.";

/// Verbs this CLI will pass to preserve.py. Never "linux". Never flash.
const PRESERVE_VERBS: &[&str] = &["backup", "all"];

#[derive(Parser, Debug)]
#[command(
    name = "fc-preserve",
    about = "Walk + sit the FC-Preserve device tree, and run the Python preserve engine for backup/all.",
    long_about = "The snapshot JSON is the Vision-menu contract.\n\
                  Other machines load ~/.grok/pool/hotpipe/fc-preserve-tree.json.\n\
                  backup/all exec python3 <repo>/fc-preserve/preserve.py <verb> <device>\n\
                  (default device GrokBotBaby), stream child stdout/stderr, exit with the child.\n\
                  ready is an honest mux/pair/en9 check — ready:true only if idevice_id lists a UDID.\n\
                  This binary does not flash phones, does not start Elffin, does not call preserve.py linux,\n\
                  and is not a visionOS app."
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Walk drives / mux / vault / hotpipe / images / models and print JSON.
    /// Also writes the snapshot so other machines can load it.
    Walk,
    /// Foreground sitter. Rewrites the snapshot every 2s (notify if built).
    Sit,
    /// Print the last snapshot JSON.
    Tree,
    /// List devices from a fresh walk (groups + flash lock).
    Devices,
    /// Run python3 <repo>/fc-preserve/preserve.py backup <device>. Streams child I/O.
    Backup {
        /// Device alias.
        #[arg(default_value = DEFAULT_DEVICE)]
        device: String,
    },
    /// Run python3 <repo>/fc-preserve/preserve.py all <device>. Streams child I/O.
    All {
        /// Device alias.
        #[arg(default_value = DEFAULT_DEVICE)]
        device: String,
    },
    /// Honest mux / pair / en9 hotspot check. ready:true only if mux has a UDID.
    Ready {
        /// Device alias (printed; does not invent mux readiness).
        #[arg(default_value = DEFAULT_DEVICE)]
        device: String,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Walk => match cmd_walk() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => fail(e),
        },
        Cmd::Sit => match cmd_sit() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => fail(e),
        },
        Cmd::Tree => match cmd_tree() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => fail(e),
        },
        Cmd::Devices => match cmd_devices() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => fail(e),
        },
        Cmd::Backup { device } => run_python_preserve("backup", &resolve_device(Some(device))),
        Cmd::All { device } => run_python_preserve("all", &resolve_device(Some(device))),
        Cmd::Ready { device } => cmd_ready(&resolve_device(Some(device))),
    }
}

fn fail(e: io::Error) -> ExitCode {
    let _ = writeln!(io::stderr(), "fc-preserve: {e}");
    ExitCode::FAILURE
}

fn resolve_device(arg: Option<String>) -> String {
    match arg {
        Some(s) if !s.trim().is_empty() => s,
        _ => DEFAULT_DEVICE.to_string(),
    }
}

fn repo_root() -> io::Result<PathBuf> {
    let mut starts = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(p) = exe.parent() {
            starts.push(p.to_path_buf());
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        starts.push(cwd);
    }
    starts.push(PathBuf::from(KNOWN_REPO));

    for start in starts {
        let mut cur = start;
        for _ in 0..10 {
            if preserve_py(&cur).is_file() {
                return Ok(cur);
            }
            if !cur.pop() {
                break;
            }
        }
    }
    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "fc-preserve/preserve.py not found (repo root)",
    ))
}

fn preserve_py(root: &Path) -> PathBuf {
    root.join("fc-preserve").join("preserve.py")
}

fn run_python_preserve(verb: &str, device: &str) -> ExitCode {
    if !PRESERVE_VERBS.contains(&verb) {
        let _ = writeln!(
            io::stderr(),
            "fc-preserve: refused — this CLI does not flash and does not call preserve.py linux (verb={verb})"
        );
        return ExitCode::FAILURE;
    }
    let root = match repo_root() {
        Ok(r) => r,
        Err(e) => return fail(e),
    };
    let script = preserve_py(&root);
    if !script.is_file() {
        return fail(io::Error::new(
            io::ErrorKind::NotFound,
            format!("{} missing", script.display()),
        ));
    }
    let status = Command::new("python3")
        .arg(&script)
        .arg(verb)
        .arg(device)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match status {
        Ok(s) => match s.code() {
            Some(code) if (0..=255).contains(&code) => ExitCode::from(code as u8),
            Some(_) => ExitCode::FAILURE,
            None => ExitCode::FAILURE,
        },
        Err(e) => fail(e),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ReadyFacts {
    device: String,
    mux_udids: Vec<String>,
    pair: String,
    en9_up: bool,
    usb_nodes: Vec<String>,
}

fn ready_report(facts: &ReadyFacts) -> (bool, Vec<String>) {
    let ready = !facts.mux_udids.is_empty();
    let usb_iphone = !facts.usb_nodes.is_empty();
    let mut lines = Vec::new();
    lines.push(format!("device: {}", facts.device));
    if facts.mux_udids.is_empty() {
        lines.push("mux:".to_string());
    } else {
        lines.push(format!("mux: {}", facts.mux_udids.join(" ")));
    }
    lines.push(format!("pair: {}", facts.pair));
    lines.push(format!("en9: {}", if facts.en9_up { "up" } else { "down" }));
    if facts.usb_nodes.is_empty() {
        lines.push("usb:".to_string());
    } else {
        lines.push(format!("usb: {}", facts.usb_nodes.join(" ")));
    }
    if !ready && usb_iphone && facts.en9_up {
        lines.push(HOTSPOT_LINE.to_string());
    }
    lines.push(if ready {
        "ready:true".to_string()
    } else {
        "ready:false".to_string()
    });
    (ready, lines)
}

fn parse_mux_udids(idevice_id_l: &str) -> Vec<String> {
    idevice_id_l
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .map(|s| s.to_string())
        .collect()
}

fn parse_en9_up(ifconfig_en9: &str) -> bool {
    ifconfig_en9
        .lines()
        .any(|l| l.trim() == "status: active")
}

fn parse_usb_iphone_nodes(ioreg: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in ioreg.lines() {
        let Some(idx) = line.find("+-o ") else {
            continue;
        };
        let rest = &line[idx + 4..];
        let name = rest.split_whitespace().next().unwrap_or("");
        if name.is_empty() {
            continue;
        }
        let low = name.to_ascii_lowercase();
        if low.starts_with("iphone") || low.starts_with("ipad") {
            out.push(name.to_string());
        }
    }
    out
}

fn cmd_output(bin: &str, args: &[&str]) -> (i32, String) {
    match Command::new(bin).args(args).output() {
        Ok(out) => {
            let mut text = String::new();
            text.push_str(&String::from_utf8_lossy(&out.stdout));
            if !out.stderr.is_empty() {
                if !text.is_empty() && !text.ends_with('\n') {
                    text.push('\n');
                }
                text.push_str(&String::from_utf8_lossy(&out.stderr));
            }
            (out.status.code().unwrap_or(1), text)
        }
        Err(e) => (-1, format!("{bin}: {e}")),
    }
}

fn gather_ready(device: &str) -> ReadyFacts {
    let (mux_code, mux_out) = cmd_output("idevice_id", &["-l"]);
    let mux_udids = if mux_code == -1 && mux_out.starts_with("idevice_id:") {
        Vec::new()
    } else {
        parse_mux_udids(&mux_out)
    };

    let pair = if let Some(udid) = mux_udids.first() {
        let (_c, text) = cmd_output("idevicepair", &["-u", udid, "validate"]);
        one_line(&text)
    } else {
        let (_c, text) = cmd_output("idevicepair", &["validate"]);
        one_line(&text)
    };

    let (_c, en9) = cmd_output("ifconfig", &["en9"]);
    let en9_up = parse_en9_up(&en9);

    let (_c, ioreg) = cmd_output("ioreg", &["-p", "IOUSB", "-w0"]);
    let usb_nodes = parse_usb_iphone_nodes(&ioreg);

    ReadyFacts {
        device: device.to_string(),
        mux_udids,
        pair,
        en9_up,
        usb_nodes,
    }
}

fn one_line(text: &str) -> String {
    text.lines()
        .map(|l| l.trim())
        .find(|l| !l.is_empty())
        .unwrap_or("")
        .to_string()
}

fn cmd_ready(device: &str) -> ExitCode {
    let facts = gather_ready(device);
    let (ready, lines) = ready_report(&facts);
    for line in &lines {
        println!("{line}");
    }
    if ready {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn cmd_walk() -> io::Result<()> {
    let snap = sit_once()?;
    println!("{}", serde_json::to_string_pretty(&snap).unwrap());
    let _ = writeln!(io::stderr(), "wrote {}", snap.snapshot_path);
    Ok(())
}

fn cmd_sit() -> io::Result<()> {
    let path = snapshot_path();
    let _ = writeln!(
        io::stderr(),
        "sitting → {}  (poll 2s, notify if built). Ctrl-C to stop. No Elffin. No flash.",
        path.display()
    );
    sit_once()?;
    sit_loop()
}

fn cmd_tree() -> io::Result<()> {
    let path = snapshot_path();
    match load_snapshot(&path) {
        Ok(snap) => {
            println!("{}", serde_json::to_string_pretty(&snap).unwrap());
            Ok(())
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            let snap = walk_snapshot();
            write_snapshot_atomic(&path, &snap)?;
            println!("{}", serde_json::to_string_pretty(&snap).unwrap());
            Ok(())
        }
        Err(e) => Err(e),
    }
}

fn cmd_devices() -> io::Result<()> {
    let snap = walk_snapshot();
    println!(
        "host {}  schema {}  generated {}",
        snap.host, snap.schema, snap.generated_at
    );
    for g in &snap.groups {
        println!("\n[{}]", g.title);
        for id in &g.ids {
            if let Some(n) = snap.node(id) {
                print_node(n, 0);
            }
        }
    }
    Ok(())
}

fn print_node(n: &fc_preserve_core::Node, indent: usize) {
    let pad = "  ".repeat(indent);
    let space = match (n.used, n.free) {
        (None, None) => "used —  free —".to_string(),
        (u, f) => format!("used {}  free {}", fmt_opt(u), fmt_opt(f)),
    };
    let sel = if n.selected { " selected" } else { "" };
    let flash = if n.flashable { " flashable" } else { " locked" };
    println!(
        "{pad}{id:<16} {kind:<8} {name:<16} {space}{sel}{flash}  {path}",
        id = n.id,
        kind = n.kind.as_str(),
        name = n.name,
        path = n.path
    );
    for k in &n.kids {
        print_node(k, indent + 1);
    }
}

fn fmt_opt(v: Option<u64>) -> String {
    match v {
        None => "—".into(),
        Some(n) => {
            if n >= 1 << 30 {
                format!("{:.1}G", n as f64 / (1u64 << 30) as f64)
            } else if n >= 1 << 20 {
                format!("{:.1}M", n as f64 / (1u64 << 20) as f64)
            } else if n >= 1 << 10 {
                format!("{:.1}K", n as f64 / (1u64 << 10) as f64)
            } else {
                format!("{n}B")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_device_is_baby() {
        assert_eq!(resolve_device(None), "GrokBotBaby");
        assert_eq!(resolve_device(Some(String::new())), "GrokBotBaby");
        assert_eq!(resolve_device(Some("  ".into())), "GrokBotBaby");
        assert_eq!(resolve_device(Some("Brick".into())), "Brick");
    }

    #[test]
    fn preserve_verbs_never_linux() {
        assert_eq!(PRESERVE_VERBS, &["backup", "all"]);
        assert!(!PRESERVE_VERBS.contains(&"linux"));
    }

    #[test]
    fn clap_backup_and_all_default_device() {
        let cli = Cli::try_parse_from(["fc-preserve", "backup"]).unwrap();
        match cli.cmd {
            Cmd::Backup { device } => assert_eq!(device, "GrokBotBaby"),
            _ => panic!("expected backup"),
        }
        let cli = Cli::try_parse_from(["fc-preserve", "all"]).unwrap();
        match cli.cmd {
            Cmd::All { device } => assert_eq!(device, "GrokBotBaby"),
            _ => panic!("expected all"),
        }
        let cli = Cli::try_parse_from(["fc-preserve", "ready", "Brick"]).unwrap();
        match cli.cmd {
            Cmd::Ready { device } => assert_eq!(device, "Brick"),
            _ => panic!("expected ready"),
        }
    }

    #[test]
    fn clap_has_no_linux_subcommand() {
        assert!(Cli::try_parse_from(["fc-preserve", "linux"]).is_err());
        assert!(Cli::try_parse_from(["fc-preserve", "linux", "GrokBotBaby"]).is_err());
    }

    #[test]
    fn ready_true_only_when_mux_has_udid() {
        let (ready, lines) = ready_report(&ReadyFacts {
            device: "GrokBotBaby".into(),
            mux_udids: vec!["4ea7e05b3045f0e9036275125a85225dd6dd9bb9".into()],
            pair: "SUCCESS: Validated pairing with device".into(),
            en9_up: true,
            usb_nodes: vec!["iPhone@02116000".into()],
        });
        assert!(ready);
        assert!(lines.iter().any(|l| l == "ready:true"));
        assert!(!lines.iter().any(|l| l == "ready:false"));
        assert!(!lines.iter().any(|l| l.contains("hotspot")));
        assert_eq!(lines[1], "mux: 4ea7e05b3045f0e9036275125a85225dd6dd9bb9");
    }

    #[test]
    fn ready_false_and_hotspot_line_when_usb_en9_empty_mux() {
        let (ready, lines) = ready_report(&ReadyFacts {
            device: "GrokBotBaby".into(),
            mux_udids: vec![],
            pair: "No device found.".into(),
            en9_up: true,
            usb_nodes: vec!["iPhone@02116000".into()],
        });
        assert!(!ready);
        assert!(lines.iter().any(|l| l == HOTSPOT_LINE));
        assert!(lines.iter().any(|l| l == "ready:false"));
        assert!(!lines.iter().any(|l| l == "ready:true"));
        assert_eq!(lines[1], "mux:");
    }

    #[test]
    fn ready_never_faked_when_mux_empty() {
        let cases = [
            ReadyFacts {
                device: "GrokBotBaby".into(),
                mux_udids: vec![],
                pair: "No device found.".into(),
                en9_up: false,
                usb_nodes: vec![],
            },
            ReadyFacts {
                device: "GrokBotBaby".into(),
                mux_udids: vec![],
                pair: "No device found.".into(),
                en9_up: false,
                usb_nodes: vec!["iPhone@02116000".into()],
            },
            ReadyFacts {
                device: "GrokBotBaby".into(),
                mux_udids: vec![],
                pair: "No device found.".into(),
                en9_up: true,
                usb_nodes: vec![],
            },
        ];
        for facts in cases {
            let (ready, lines) = ready_report(&facts);
            assert!(!ready, "facts={facts:?}");
            assert!(lines.iter().any(|l| l == "ready:false"));
            assert!(!lines.iter().any(|l| l == "ready:true"));
        }
    }

    #[test]
    fn parse_mux_does_not_invent_udid() {
        assert!(parse_mux_udids("").is_empty());
        assert!(parse_mux_udids("\n\n  \n").is_empty());
        assert_eq!(
            parse_mux_udids("4ea7e05b3045f0e9036275125a85225dd6dd9bb9\n"),
            vec!["4ea7e05b3045f0e9036275125a85225dd6dd9bb9"]
        );
    }

    #[test]
    fn parse_en9_and_usb_from_live_shapes() {
        let en9 = "\
en9: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 169.254.176.182 netmask 0xffff0000 broadcast 169.254.255.255
	status: active
";
        assert!(parse_en9_up(en9));
        assert!(!parse_en9_up("ifconfig: interface en9 does not exist\n"));
        let ioreg = "\
+-o Root  <class IORegistryEntry>
  |   +-o iPhone@02116000  <class IOUSBHostDevice, id 0x100002ac8>
  |   +-o ShuttlePRO v2@02111000  <class IOUSBHostDevice>
";
        assert_eq!(parse_usb_iphone_nodes(ioreg), vec!["iPhone@02116000"]);
        assert!(parse_usb_iphone_nodes("+-o USB2 Hub@02100000\n").is_empty());
    }
}
