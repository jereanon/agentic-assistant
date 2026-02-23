# nix-darwin module for Herald — runs as a launchd user agent.
#
# Usage in a nix-darwin flake configuration:
#
#   {
#     inputs.herald.url = "github:jereanon/herald";
#
#     darwinConfigurations.myhost = nix-darwin.lib.darwinSystem {
#       modules = [
#         herald.darwinModules.default
#         {
#           services.herald = {
#             enable = true;
#             configFile = ./herald.toml;
#             dataDir = "/Users/me/.herald";
#           };
#         }
#       ];
#     };
#   }
flake:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.herald;
  defaultPackage = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ ./shared-options.nix ];

  config = lib.mkIf cfg.enable {
    services.herald.package = lib.mkDefault defaultPackage;

    launchd.user.agents.herald = {
      command = "${cfg.package}/bin/herald --config ${cfg.configFile}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        WorkingDirectory = cfg.dataDir;

        StandardOutPath = "${cfg.dataDir}/herald.log";
        StandardErrorPath = "${cfg.dataDir}/herald.err";

        EnvironmentVariables = {
          HERALD_DATA_DIR = cfg.dataDir;
        }
        // lib.optionalAttrs (cfg.claudeCredentialsFile != null) {
          CLAUDE_CREDENTIALS_FILE = cfg.claudeCredentialsFile;
        }
        // cfg.extraEnvironment;
      };
    };
  };
}
