use std::io;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::time::Duration;

use crate::node::Snapshot;
use crate::paths::{snapshot_path, write_snapshot_atomic};
use crate::walk::{walk_with, WalkConfig};

const POLL: Duration = Duration::from_secs(2);

/// Foreground sitter. Rewrites the snapshot JSON every 2s, or sooner if
/// `notify` is built and a watched path changes. Other machines / a Vision
/// menu load that file. Never starts Elffin or a phone flash.
pub fn sit_loop() -> io::Result<()> {
    sit_loop_until(Arc::new(AtomicBool::new(true)))
}

/// Same as `sit_loop`, but stops when `running` is false (tests).
pub fn sit_loop_until(running: Arc<AtomicBool>) -> io::Result<()> {
    let path = snapshot_path();
    let watch_dirs = sit_watch_dirs();
    let rx = start_notify(&watch_dirs);

    let mut last_json = String::new();
    while running.load(Ordering::Relaxed) {
        let mut cfg = WalkConfig::default();
        cfg.source = "sit".into();
        let snap = walk_with(&cfg);
        write_if_changed(&path, &snap, &mut last_json)?;

        match &rx {
            Some(rx) => match rx.recv_timeout(POLL) {
                Ok(_) => {
                    // drain a burst so one rewrite covers a flurry
                    while rx.try_recv().is_ok() {}
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => {
                    std::thread::sleep(POLL);
                }
            },
            None => std::thread::sleep(POLL),
        }
    }
    Ok(())
}

/// One-shot sit write (walk + persist). Used by the CLI `walk` command too.
pub fn sit_once() -> io::Result<Snapshot> {
    let mut cfg = WalkConfig::default();
    cfg.source = "walk".into();
    let snap = walk_with(&cfg);
    write_snapshot_atomic(&cfg.snapshot_path, &snap)?;
    Ok(snap)
}

fn write_if_changed(path: &std::path::Path, snap: &Snapshot, last: &mut String) -> io::Result<()> {
    let body = serde_json::to_string(snap).unwrap_or_default();
    if body == *last {
        return Ok(());
    }
    write_snapshot_atomic(path, snap)?;
    *last = body;
    Ok(())
}

fn sit_watch_dirs() -> Vec<PathBuf> {
    let cfg = WalkConfig::default();
    let mut dirs = vec![cfg.hotpipe.clone(), cfg.vault.clone(), cfg.images.clone()];
    dirs.push(cfg.hf_hub);
    dirs.push(cfg.lmstudio);
    dirs.retain(|p| p.is_dir());
    dirs
}

#[cfg(feature = "watch")]
fn start_notify(dirs: &[PathBuf]) -> Option<mpsc::Receiver<()>> {
    use notify::{RecommendedWatcher, RecursiveMode, Watcher};

    if dirs.is_empty() {
        return None;
    }
    let (tx, rx) = mpsc::channel();
    let mut watcher = RecommendedWatcher::new(
        move |res: Result<notify::Event, notify::Error>| {
            if res.is_ok() {
                let _ = tx.send(());
            }
        },
        notify::Config::default(),
    )
    .ok()?;
    for d in dirs {
        // hotpipe is noisy; non-recursive is enough. vault/images too.
        let _ = watcher.watch(d, RecursiveMode::NonRecursive);
    }
    // watcher must live — leak it for the process lifetime of `sit`
    std::mem::forget(watcher);
    Some(rx)
}

#[cfg(not(feature = "watch"))]
fn start_notify(_dirs: &[PathBuf]) -> Option<mpsc::Receiver<()>> {
    None
}
