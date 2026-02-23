# herald

[![CI](https://github.com/jamesbrink/herald/actions/workflows/ci.yml/badge.svg)](https://github.com/jamesbrink/herald/actions/workflows/ci.yml)
[![Nix Flake](https://img.shields.io/badge/Nix_Flake-enabled-blue.svg?logo=nixos)](https://nixos.wiki/wiki/Flakes)
[![Rust](https://img.shields.io/badge/Rust-stable-orange.svg?logo=rust)](https://www.rust-lang.org)

A self-hostable AI assistant with web UI, Discord bot, scheduled tasks, and multi-agent support. Built on [orra](https://github.com/jereanon/orra).

## Quick Start

1. Copy `config.example.toml` to `assistant.toml`
2. `cargo run --release` (or use Nix — see below)
3. Open <http://localhost:8080> and enter your API key

API keys can be auto-detected from the Claude CLI keychain (macOS), `ANTHROPIC_API_KEY` env var, or entered via the web UI at runtime.

## Configuration

See [config.example.toml](config.example.toml) for all available options.

## Nix

Herald provides a Nix flake with packages, a dev shell, Docker image, and an overlay.

### Run directly from GitHub

No clone needed — run the latest commit from `main`:

```sh
nix run github:jereanon/herald
```

Or pin to a specific branch/revision:

```sh
nix run github:jereanon/herald/<branch>
nix run github:jereanon/herald/<commit-sha>
```

Herald expects an `assistant.toml` in the working directory. Create one from the example config first, or run with an empty file to use the web UI setup screen.

### Build locally

```sh
nix build          # result/bin/herald
nix run .          # build and run
```

### Dev shell

The flake includes a dev shell with `cargo`, `rustc`, `clippy`, `rustfmt`, `rust-analyzer`, and other tools:

```sh
nix develop        # enter the shell
cargo build        # build with cargo inside the shell
cargo test         # run tests
cargo clippy       # lint
```

With [direnv](https://direnv.net/), the shell activates automatically when you `cd` into the project.

### Docker image (Linux only)

```sh
nix build .#dockerImage
docker load < result
docker run --rm -p 8080:8080 \
  -v ./assistant.toml:/assistant.toml:ro \
  -e ANTHROPIC_API_KEY \
  herald:<tag>
```

### Install as a package

Add Herald to your flake inputs and use the overlay or package directly.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    herald.url = "github:jereanon/herald";
    herald.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, herald, ... }: {
    # Option 1: use the overlay
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ herald.overlays.default ]; }
        # herald is now available as pkgs.herald
      ];
    };

    # Option 2: reference the package directly
    # herald.packages.x86_64-linux.default
  };
}
```

### Run as a NixOS service

Herald ships NixOS and nix-darwin modules:

```nix
# NixOS
{
  imports = [ herald.nixosModules.default ];

  services.herald = {
    enable = true;
    configFile = ./assistant.toml;
  };
}

# nix-darwin
{
  imports = [ herald.darwinModules.default ];

  services.herald = {
    enable = true;
    configFile = ./assistant.toml;
  };
}
```

Session data and cron state persist under `/var/lib/herald/`.

### Supported platforms

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## License

MIT
