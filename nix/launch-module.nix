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
    environments = lib.mapAttrs (_: e: { inherit (e) units progressFile; }) cfg.environments;
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
        options.progressFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            A JSON file the environment writes while it starts:
            {step, steps, label, started, since, expected, error}. The Launcher shows
            it as progress (#232).
          '';
        };
      });
    };
    launcher = {
      enable = lib.mkEnableOption "the Launcher window (a local web page with a card per environment)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8790;
        description = "The Launcher listens on 127.0.0.1 at this port.";
      };
      autoStart = {
        environment = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            An environment the Launcher starts by itself after `delaySeconds`
            (#238), unless the user cancels it on the page or starts or stops
            something first. For machines that run unattended.
          '';
        };
        delaySeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60;
          description = "Seconds after the Launcher starts before the automatic start.";
        };
      };
    };
    autostart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Environments started at boot (launch <id> --yes, after the preflight).";
    };
    autostartFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A file read at boot: more environments to start, one id per line
        (lines starting with # are ignored). Missing file: nothing extra.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      map
        (id: {
          assertion = builtins.elem id catalogIds;
          message = "services.launch: environment '${id}' is not in environments/catalog.toml.";
        })
        (lib.attrNames cfg.environments ++ cfg.autostart
          ++ lib.optional (cfg.launcher.autoStart.environment != null) cfg.launcher.autoStart.environment)
      ++ map
        (id: {
          assertion = cfg.environments ? ${id};
          message = "services.launch.autostart: '${id}' has no units in services.launch.environments.";
        })
        cfg.autostart;

    environment.systemPackages = [ launch.cli ]
      ++ lib.optionals cfg.launcher.enable [
      launch.launcher
      (pkgs.makeDesktopItem {
        name = "launcher";
        desktopName = "Launcher";
        genericName = "Omgevingen starten";
        comment = "Kies een omgeving om te proberen";
        exec = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:${toString cfg.launcher.port}/";
        icon = "applications-other";
        categories = [ "Office" ];
      })
    ];

    # The Launcher runs in each graphical user session, as that user.
    systemd.user.services.launcher = lib.mkIf cfg.launcher.enable {
      description = "Launcher: start, stop and open environments (http://127.0.0.1:${toString cfg.launcher.port}/)";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      environment.LAUNCH_CONFIG = "/etc/launch/config.json";
      serviceConfig = {
        ExecStart = "${launch.launcher}/bin/launcher --port ${toString cfg.launcher.port}"
          + lib.optionalString (cfg.launcher.autoStart.environment != null)
          " --auto-start ${cfg.launcher.autoStart.environment} --auto-start-delay ${toString cfg.launcher.autoStart.delaySeconds}";
        Restart = "on-failure";
      };
    };
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

    systemd.services.launch-autostart = lib.mkIf (cfg.autostart != [ ] || cfg.autostartFile != null) {
      description = "Launch: start the environments marked to start at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      environment.LAUNCH_CONFIG = "/etc/launch/config.json";
      script = ''
        ids=${lib.escapeShellArg (lib.concatStringsSep " " cfg.autostart)}
        ${lib.optionalString (cfg.autostartFile != null) ''
          f=${lib.escapeShellArg cfg.autostartFile}
          if [ -r "$f" ]; then
            ids="$ids $(${pkgs.gnused}/bin/sed -e 's/#.*//' "$f" | ${pkgs.coreutils}/bin/tr -s ' \t\r\n' ' ')"
          fi
        ''}
        for id in $ids; do
          ${launch.cli}/bin/launch "$id" --yes </dev/null || echo "launch-autostart: $id did not start" >&2
        done
      '';
    };
  };
}
