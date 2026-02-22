# NixOS module for Herald — runs as a systemd service.
#
# Usage in a NixOS flake configuration:
#
#   {
#     inputs.herald.url = "github:jereanon/herald";
#
#     nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
#       modules = [
#         herald.nixosModules.default
#         {
#           services.herald = {
#             enable = true;
#             configFile = ./herald.toml;
#             environmentFile = "/run/secrets/herald.env";
#           };
#         }
#       ];
#     };
#   }
flake:

{ config, lib, pkgs, ... }:

let
  cfg = config.services.herald;
  defaultPackage = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ ./shared-options.nix ];

  config = lib.mkIf cfg.enable {
    services.herald.package = lib.mkDefault defaultPackage;

    # Create a dedicated system user and group.
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Herald AI assistant";
    };
    users.groups.${cfg.group} = { };

    systemd.services.herald = {
      description = "Herald AI Assistant";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        # Override data_dir so Herald writes state to the expected location
        # regardless of what the config file says.
        HERALD_DATA_DIR = cfg.dataDir;
      } // cfg.extraEnvironment;

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/herald --config ${cfg.configFile}";
        Restart = "on-failure";
        RestartSec = 5;

        User = cfg.user;
        Group = cfg.group;

        WorkingDirectory = cfg.dataDir;
        StateDirectory = "herald";
        StateDirectoryMode = "0750";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.dataDir ];
      } // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
