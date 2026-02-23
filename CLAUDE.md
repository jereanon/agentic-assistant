# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Cargo (inside nix develop or with a Rust toolchain)
cargo build --release          # Build
cargo run --release             # Run with default config (assistant.toml)
cargo run --release -- --config path/to/config.toml
cargo run --release -- --check  # Validate config without starting
cargo test                      # Run tests (identity, config, federation)
cargo clippy                    # Lint
cargo fmt                       # Format

# Nix
nix build                       # Build (result/bin/herald)
nix run .                       # Build and run
nix flake check                 # Run all checks (build, clippy, tests, treefmt)
nix fmt                         # Format Nix and Rust files via treefmt
```

Configuration file defaults to `assistant.toml` (copy from `config.example.toml`). API keys can be auto-detected from the Claude CLI keychain (macOS), `ANTHROPIC_API_KEY` env var, or entered via the web UI at runtime.

## Architecture

Herald is a self-hostable AI assistant built on the [orra](https://github.com/jereanon/orra) library, which provides the core LLM runtime, tool system, session management, and channel adapters. Herald itself is the configuration layer, orchestration, and web UI on top of orra.

### Source Layout (`src/`)

- **`main.rs`** - Entry point and orchestration. Loads config, initializes the provider (Claude/OpenAI), sets up the tool registry, hook registry, session store, cron service, and starts Discord/web server. Supports single-agent and multi-agent modes.
- **`config.rs`** - TOML configuration parsing with `${ENV_VAR}` substitution. Defines all config structs (`Config`, `AgentConfig`, `ProviderConfig`, `ToolsConfig`, `DiscordConfig`, `GatewayConfig`, etc.).
- **`identity.rs`** - Builds system prompts from agent personality + available tools. Auto-generates tool capability descriptions. Has unit tests.
- **`discord_manager.rs`** - Discord bot lifecycle (connect/disconnect at runtime). Routes messages to the correct agent via @mention matching in multi-agent mode.
- **`tools.rs`** - Conditional tool registration based on config toggles. Registers Discord, web, memory, exec, documents, image-gen, delegation, claude-code, and cron tools.
- **`tools/claude_code.rs`** - Placeholder module for the Claude Code tool. Registration wired via `orra::tools::claude_code::register_tools`.
- **`federation/mod.rs`** - Federation hub: peer registry, mDNS discovery, health tracking, and remote agent routing. Enables cross-instance agent collaboration.
- **`federation/api.rs`** - Axum routes for federation endpoints (peer registration, agent listing, message forwarding).
- **`federation/client.rs`** - HTTP client for communicating with remote herald instances.
- **`federation/discovery.rs`** - mDNS-based automatic peer discovery on local networks.
- **`federation/tool.rs`** - `federation_send` tool allowing agents to message remote agents on federated peers.
- **`web.rs`** - Web module root. Axum router setup, CORS, security headers, embedded static asset serving via `rust-embed`, and SPA fallback routing.
- **`web/handlers.rs`** - Axum HTTP handlers. REST API for config, sessions, settings, agents, cron jobs, Discord management, and federation peers. Serves the embedded SPA.
- **`web/ws.rs`** - WebSocket handler for real-time streaming. Routes @mentions to specific agents. Handles approval hook request/response flow.
- **`web/static/index.html`** - Embedded single-page web UI (~4000 lines, React/TypeScript).
- **`hooks.rs`** - Re-exports hook setup (logging, approval, working directory hooks).
- **`provider_wrapper.rs`** - `DynamicProvider` wrapper enabling hot-swap of LLM providers at runtime.

### Key Design Patterns

- **Hot-swappable provider**: `DynamicProvider` wraps Claude/OpenAI behind `Arc<RwLock<>>`, allowing runtime model/provider changes via the web API.
- **Multi-agent**: Multiple named agents share a provider and tool registry. Messages are routed by @mention. Agents can delegate to each other.
- **Approval hooks**: Built-in permission system for dangerous operations (exec, etc.) with WebSocket-based approval flow.
- **MCP integration**: External tool servers connected via stdio transport, configured in TOML.
- **Context budgeting**: Token limits with reserved output buffer, configurable per deployment.
- **Federation**: Peer-to-peer agent communication across herald instances. Peers discovered via mDNS or manual registration. Agents can mention and message remote agents.

### Modes of Operation

1. **Web-only** (default) - Gateway auto-enables when no Discord token is set
2. **Discord-only** - Discord token provided, gateway disabled
3. **Hybrid** - Both Discord and web UI active simultaneously

### Core Dependency

Nearly all LLM/tool/session functionality comes from the `orra` crate (git dependency). Herald's feature flags on orra control what capabilities are compiled in: `claude`, `openai`, `discord`, `gateway`, `file-store`, `parallel-tools`, `documents`, `mcp`, `claude-code`, `web-fetch`, `web-search`, `browser`, `image-gen`, `federation`.
