use serde::{Deserialize, Serialize};

use crate::kinds::Kind;

pub const TREE_SCHEMA: &str = "fc-preserve-tree/v1";

/// One menu row. The tree *is* the Vision menu: walk `kids` the same way a
/// submenu walks children. `used`/`free` are bytes, or null when unknown.
/// Never invent capacities.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Node {
    pub id: String,
    pub kind: Kind,
    pub name: String,
    pub path: String,
    pub used: Option<u64>,
    pub free: Option<u64>,
    #[serde(default)]
    pub kids: Vec<Node>,
    pub selected: bool,
    pub flashable: bool,
}

impl Node {
    pub fn empty(id: impl Into<String>, kind: Kind, name: impl Into<String>, path: impl Into<String>) -> Self {
        let id = id.into();
        let path = path.into();
        let flashable = crate::kinds::flashable_for(&id, kind, &path);
        Self {
            id,
            kind,
            name: name.into(),
            path,
            used: None,
            free: None,
            kids: Vec::new(),
            selected: false,
            flashable,
        }
    }

    pub fn with_space(mut self, used: Option<u64>, free: Option<u64>) -> Self {
        self.used = used;
        self.free = free;
        self
    }

    pub fn with_kids(mut self, kids: Vec<Node>) -> Self {
        self.kids = kids;
        self
    }

    pub fn with_selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Group {
    pub title: String,
    pub ids: Vec<String>,
}

/// Snapshot written to `~/.grok/pool/hotpipe/fc-preserve-tree.json`.
/// Other machines and a Vision ornament load this file (HTTP later).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Snapshot {
    pub schema: String,
    pub generated_at: String,
    pub host: String,
    pub source: String,
    pub snapshot_path: String,
    pub groups: Vec<Group>,
    pub nodes: Vec<Node>,
}

impl Snapshot {
    pub fn node(&self, id: &str) -> Option<&Node> {
        self.nodes.iter().find(|n| n.id == id)
    }
}
