//! Re-exports the Claude Code tool from the agentic-rs library.
//!
//! Configuration is handled in this crate's config module; registration
//! wires it up via `agentic_rs::tools::claude_code::register_tools`.

pub use agentic_rs::tools::claude_code::{ClaudeCodeConfig, ClaudeCodeTool, ClaudeCodeResumeTool};
