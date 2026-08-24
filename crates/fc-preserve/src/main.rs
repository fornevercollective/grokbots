use std::io::{self, Write};
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use fc_preserve_core::{
    load_snapshot, sit_loop, sit_once, snapshot_path, walk_snapshot, write_snapshot_atomic,
};

#[derive(Parser, Debug)]
#[command(
    name = "fc-preserve",
    about = "Walk + sit the FC-Preserve device tree. Portable Rust core; Swift paint is Mini-only.",
    long_about = "The snapshot JSON is the Vision-menu contract.\n\
                  Other machines load ~/.grok/pool/hotpipe/fc-preserve-tree.json.\n\
                  This binary does not flash phones, does not start Elffin, and is not a visionOS app."
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
    }
}

fn fail(e: io::Error) -> ExitCode {
    let _ = writeln!(io::stderr(), "fc-preserve: {e}");
    ExitCode::FAILURE
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
