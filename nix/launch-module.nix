# services.launch: the NixOS side of Launch (ADR 0008,
# docs/adr/0008-launch-environments.md). Generic: nothing here is specific to
# one workplace; a host binds each environment of the catalogue to the
# systemd units that start and stop it.
#
#   services.launch = {
#     enable = true;
#     dataPath = "/var/lib/...";            # free space is checked here
#     environments.mijn-bureau.units = [ "guest.service" "deploy.service" ];
#     autostart = [ "mijn-bureau" ];        # started at boot (launch <id> --yes)
#   };
#
# It installs the `launch` command, writes /etc/launch/config.json (read by
# launch/launch.sh) and adds a polkit rule: members of `group` may start, stop
# and restart exactly the bound units, without sudo.
#
# Experimental and unofficial. Not for production.
{ launch }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.launch;
  allUnits = lib.unique (lib.concatMap (e: e.units) (lib.attrValues cfg.environments));
  configJson = pkgs.writeText "launch-config.json" (builtins.toJSON {
    inherit (cfg) dataPath reserveGiB internetUrl;
    environments = lib.mapAttrs (_: e: { inherit (e) units; }) cfg.environments;
  });
  catalogIds = map (e: e.id) launch.catalog.environments;
in
{
  options.services.launch = {
    enable = lib.mkEnableOption "Launch: start environments of the catalogue on demand";

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/launch";
      description = "Where environments keep their data; the preflight checks the free space here.";
    };
    reserveGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 6;
      description = "Memory kept for the workplace itself when the preflight compares memory.";
    };
    internetUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/";
      description = "A URL that answers when there is internet (preflight).";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "launch";
      description = "Members may start and stop the bound units without sudo (polkit).";
    };
    environments = lib.mkOption {
      default = { };
      description = "Per environment id of the catalogue: the systemd units that start it, in order.";
      type = lib.types.attrsOf (lib.types.submodule {
        options.units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "systemd units, started in this order and stopped in reverse.";
        };
      });
    };
    autostart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Environments started at boot (launch <id> --yes, after the preflight).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      map
        (id: {
          assertion = builtins.elem id catalogIds;
          message = "services.launch: environment '${id}' is not in environments/catalog.toml.";
        })
        (lib.attrNames cfg.environments ++ cfg.autostart)
      ++ map
        (id: {
          assertion = cfg.environments ? ${id};
          message = "services.launch.autostart: '${id}' has no units in services.launch.environments.";
        })
        cfg.autostart;

    environment.systemPackages = [ launch.cli ];
    environment.etc."launch/config.json".source = configJson;
    users.groups.${cfg.group} = { };

    security.polkit.extraConfig = lib.mkIf (allUnits != [ ]) ''
      // Launch (ADR 0008): members of ${cfg.group} start and stop environments.
      polkit.addRule(function (action, subject) {
        var units = ${builtins.toJSON allUnits};
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup(${builtins.toJSON cfg.group}) &&
            units.indexOf(action.lookup("unit")) >= 0 &&
            ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0) {
          return polkit.Result.YES;
        }
      });
    '';

    systemd.services.launch-autostart = lib.mkIf (cfg.autostart != [ ]) {
      description = "Launch: start the environments marked to start at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      environment.LAUNCH_CONFIG = "/etc/launch/config.json";
      script = lib.concatMapStrings
        (id: ''
          ${launch.cli}/bin/launch ${lib.escapeShellArg id} --yes </dev/null || echo "launch-autostart: ${id} did not start" >&2
        '')
        cfg.autostart;
    };
  };
}
