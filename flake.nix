{
  description = "Herald — a self-hostable AI assistant built on orra";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, rust-overlay, ... }:
    let
      # Systems we support
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Per-system outputs (packages, devShells, etc.)
      perSystem = flake-utils.lib.eachSystem supportedSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          # Use stable Rust from the overlay
          rustToolchain = pkgs.rust-bin.stable.latest.default;

          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          # Source filtering — only include Rust source + static assets
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              # Include static web assets (HTML, CSS, JS, etc.)
              (pkgs.lib.hasInfix "/src/web/static/" path)
              # Include config example for reference
              || (builtins.baseNameOf path == "config.example.toml")
              # Include everything crane normally includes (Rust sources, Cargo.*)
              || (craneLib.filterCargoSources path type);
          };

          # Common arguments shared between dep-only and full builds
          commonArgs = {
            inherit src;
            strictDeps = true;

            nativeBuildInputs = with pkgs; [
              pkg-config
            ];

            buildInputs = with pkgs; [
              openssl
            ];
          };

          # Build only the cargo dependencies (for caching)
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # Build the full herald binary
          herald = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;

            # Install the example config alongside the binary
            postInstall = ''
              mkdir -p $out/share/herald
              cp config.example.toml $out/share/herald/
            '';
          });
        in
        {
          packages = {
            inherit herald;
            default = herald;
          };

          checks = {
            inherit herald;

            # Run clippy
            herald-clippy = craneLib.cargoClippy (commonArgs // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets";
            });

            # Run tests
            herald-tests = craneLib.cargoTest (commonArgs // {
              inherit cargoArtifacts;
            });
          };

          devShells.default = craneLib.devShell {
            checks = self.checks.${system};

            packages = with pkgs; [
              rust-analyzer
            ];
          };
        }
      );
    in
    # Merge per-system outputs with system-independent outputs (modules)
    perSystem // {
      nixosModules.default = import ./nix/nixos-module.nix self;
      darwinModules.default = import ./nix/darwin-module.nix self;
    };
}
