//! Re-exports the dynamic provider from the agentic library.
//!
//! The implementation has been moved to `agentic_rs::providers::dynamic`.
//! This module re-exports the types for backward compatibility within
//! this crate.

pub use agentic_rs::providers::dynamic::{DynamicProvider, PlaceholderProvider};
