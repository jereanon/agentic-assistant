{
  description = "Herald — a self-hostable AI assistant built on orra";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    crane.url = "github:ipetkov/crane";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      crane,
      rust-overlay,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        overlays.default = final: _prev: {
          herald = self.packages.${final.system}.default;
        };
        nixosModules.default = import ./nix/nixos-module.nix self;
        darwinModules.default = import ./nix/darwin-module.nix self;
      };

      perSystem =
        {
          lib,
          system,
          ...
        }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "clippy"
              "rust-src"
              "rustfmt"
            ];
          };

          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          src = lib.cleanSourceWith {
            src = self;
            filter =
              path: type:
              (craneLib.filterCargoSources path type)
              || (builtins.match ".*/src/web/static/.*" path != null)
              || (builtins.baseNameOf path == "config.example.toml");
          };

          commonArgs = {
            inherit src;
            strictDeps = true;

            nativeBuildInputs = with pkgs; [
              pkg-config
            ];

            buildInputs =
              with pkgs;
              [
                openssl
              ]
              ++ lib.optionals pkgs.stdenv.isDarwin [
                apple-sdk_15
                libiconv
              ];
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          herald = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              postInstall = ''
                mkdir -p $out/share/herald
                cp config.example.toml $out/share/herald/
              '';
            }
          );
        in
        {
          packages = {
            default = herald;
            herald = herald;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            dockerImage = pkgs.dockerTools.buildLayeredImage {
              name = "herald";
              tag = self.shortRev or "dirty";
              created =
                let
                  d = self.lastModifiedDate or "19700101000000";
                in
                "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}T${builtins.substring 8 2 d}:${builtins.substring 10 2 d}:${builtins.substring 12 2 d}Z";
              contents = [ pkgs.cacert ];
              config = {
                Cmd = [ "${herald}/bin/herald" ];
                Env = [
                  "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                ];
                ExposedPorts."8080/tcp" = { };
              };
            };
          };

          checks = {
            inherit herald;

            herald-clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            herald-fmt = craneLib.cargoFmt {
              inherit src;
            };

            herald-test = craneLib.cargoTest (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );
          };

          devShells.default = craneLib.devShell {
            checks = self.checks.${system};
            packages = with pkgs; [
              cargo-watch
              cargo-edit
              rust-analyzer
            ];
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };
        };
    };
}
