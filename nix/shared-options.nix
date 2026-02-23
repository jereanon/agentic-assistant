# Shared NixOS / nix-darwin option declarations for the Herald service.
#
# Both platform modules import this file so that the option schema stays
# consistent. Only the `config` section differs (systemd vs launchd).
{ lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkPackageOption
    types
    ;
in
{
  options.services.herald = {
    enable = mkEnableOption "Herald AI assistant";

    package = mkOption {
      type = types.package;
      description = "The Herald package to use.";
    };

    configFile = mkOption {
      type = types.path;
      description = ''
        Path to the Herald configuration file (assistant.toml).
        See config.example.toml in the Herald repo for all available options.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/herald";
      description = "Base data directory for sessions, cron jobs, and other persistent data.";
    };

    user = mkOption {
      type = types.str;
      default = "herald";
      description = "User account under which Herald runs.";
    };

    group = mkOption {
      type = types.str;
      default = "herald";
      description = "Group under which Herald runs.";
    };

    claudeCredentialsFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to a Claude CLI credentials file (.credentials.json).
        When set, Herald reads the OAuth token from this file at startup,
        removing the need to manually enter an API key. Typically points
        at another user's credentials, e.g. "/home/youruser/.claude/.credentials.json".
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an environment file loaded before Herald starts.
        Useful for secrets like ANTHROPIC_API_KEY or DISCORD_TOKEN
        that you don't want in the Nix store.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to Herald.";
    };
  };
}
