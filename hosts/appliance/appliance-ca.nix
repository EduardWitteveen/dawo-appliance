# The per-install appliance CA and its trust on the host (Slice 4b, ADR 0004).
#
# THIS IS A DEMO APPLIANCE, NOT FOR PRODUCTION: the CA private key lives on
# this machine's disk (root-only) and is handed to the guest VM once via
# cloud-init (Slice 4a). Nothing outside the appliance ever trusts this CA.
#
# Why a run-time CA: `security.pki.certificateFiles` is resolved at BUILD time,
# but the CA must be unique per installation (a CA shared by every ISO would
# let anyone with the image impersonate every appliance), so it is generated at
# first boot and trusted at run time. Additions only (ADR 0003): nothing here
# overrides a user-facing upstream option; the Firefox policy merges into
# upstream's set.
#
# 1. dawo-appliance-ca.service — oneshot, idempotent: generates an EC P-256
#    CA (CN "DAWO appliance local CA", 10 years, CA:TRUE, keyCertSign/cRLSign)
#    once, if `ca.key` is absent. Files (contract for other modules):
#      <dir>/ca.crt         0644  PEM certificate (browsers, curl --cacert,
#                                 cloud-init `ca_certs`, cert-manager CA issuer)
#      <dir>/ca.key         0600  PEM private key (root only; guest transport
#                                 only through the install-time cloud-init
#                                 user-data, Slice 4a)
#      <dir>/ca.crt.sha256  0644  `sha256sum` line for the health check
#    Runs before display-manager.service; guest/cluster units declare
#    `after`/`wants` on `dawo-appliance-ca.service` (RemainAfterExit keeps it
#    "active" for them).
#
# 2. Firefox: policy `Certificates.Install = [ <dir>/ca.crt ]`, merged into
#    upstream's `programs.firefox.policies` (nixpkgs writes the merged set to
#    /etc/firefox/policies/policies.json). Firefox reads the file at start, so
#    the CA is trusted from the first session after first boot.
#
# 3. Chromium (system NSS, no certificate policy on Linux): a systemd USER
#    service imports the CA into the logged-in user's `~/.pki/nssdb` with
#    `certutil` at every login, idempotently (skips when already present with
#    the same content, replaces a stale copy, does nothing when no CA exists).
#
# 4. CLI trust: `/etc/dawo-appliance/ca.env` names the files so the appliance's
#    own scripts (health check, Slice 7) can `curl --cacert "$DAWO_APPLIANCE_CA_CERT"`.
#    The system trust bundle is NOT rewritten at run time.
{ config, lib, pkgs, ... }:

let
  cfg = config.appliance.ca;
  nick = cfg.commonName;

  generate = pkgs.writeShellScript "dawo-appliance-ca-generate" ''
    set -euo pipefail
    dir=${lib.escapeShellArg cfg.dir}
    crt=${lib.escapeShellArg cfg.certFile}
    key=${lib.escapeShellArg cfg.keyFile}

    mkdir -p "$dir"
    chmod 0755 "$dir"

    if [ -s "$key" ] && [ -s "$crt" ]; then
      echo "dawo-appliance-ca: CA already present at $crt, nothing to do"
    else
      if [ -e "$key" ] || [ -e "$crt" ]; then
        echo "dawo-appliance-ca: incomplete CA in $dir (one of ca.key/ca.crt missing or empty); regenerating" >&2
      fi
      echo "dawo-appliance-ca: generating a new per-install CA in $dir"
      tmp="$(mktemp -d "$dir/.new.XXXXXX")"
      trap 'rm -rf "$tmp"' EXIT
      (
        umask 077
        openssl req -x509 -new -noenc \
          -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
          -sha256 -days ${toString cfg.validityDays} \
          -subj ${lib.escapeShellArg "/CN=${cfg.commonName}"} \
          -addext "basicConstraints=critical,CA:TRUE" \
          -addext "keyUsage=critical,keyCertSign,cRLSign" \
          -addext "subjectKeyIdentifier=hash" \
          -keyout "$tmp/ca.key" -out "$tmp/ca.crt" 2>/dev/null
      )
      chmod 0600 "$tmp/ca.key"
      chmod 0644 "$tmp/ca.crt"
      # Key first, then certificate: a visible ca.crt always has its key.
      mv -f "$tmp/ca.key" "$key"
      mv -f "$tmp/ca.crt" "$crt"
      # A regenerated CA invalidates a previous checksum.
      rm -f "$crt.sha256"
    fi

    # Always enforce the contract modes (a restore or copy may have changed them).
    chown root:root "$key" "$crt"
    chmod 0600 "$key"
    chmod 0644 "$crt"

    if [ ! -s "$crt.sha256" ]; then
      (cd "$dir" && sha256sum "$(basename "$crt")" > "$(basename "$crt").sha256")
      chmod 0644 "$crt.sha256"
    fi
    echo "dawo-appliance-ca: $(openssl x509 -in "$crt" -noout -subject -enddate | tr '\n' ' ')"
  '';

  # Per-login NSS import for Chromium (and any other system-NSS consumer that
  # reads the user's database). Runs as the logged-in user.
  nssImport = pkgs.writeShellScript "dawo-appliance-ca-nss-import" ''
    set -euo pipefail
    crt=${lib.escapeShellArg cfg.certFile}
    nick=${lib.escapeShellArg nick}
    db="$HOME/.pki/nssdb"

    if [ ! -r "$crt" ]; then
      echo "dawo-appliance-ca-nss: no readable CA at $crt; nothing to import"
      exit 0
    fi
    mkdir -p "$db"
    chmod 0700 "$HOME/.pki" "$db"
    if [ ! -e "$db/cert9.db" ]; then
      certutil -d "sql:$db" -N --empty-password
    fi
    if certutil -d "sql:$db" -L -n "$nick" >/dev/null 2>&1; then
      # Same certificate already trusted? Compare the DER bytes.
      if cmp -s <(certutil -d "sql:$db" -L -n "$nick" -r) <(openssl x509 -in "$crt" -outform DER); then
        echo "dawo-appliance-ca-nss: '$nick' already present in $db"
        exit 0
      fi
      echo "dawo-appliance-ca-nss: replacing a stale '$nick' in $db"
      certutil -d "sql:$db" -D -n "$nick"
    fi
    certutil -d "sql:$db" -A -t "C,," -n "$nick" -i "$crt"
    echo "dawo-appliance-ca-nss: imported '$nick' into $db"
  '';
in
{
  options.appliance.ca = {
    enable = lib.mkEnableOption "the per-install appliance CA and its trust on the host (ADR 0004)" // {
      default = true;
    };

    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/dawo-appliance/ca";
      description = "Directory holding the CA files (certificate world-readable, key root-only).";
    };

    certFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dir}/ca.crt";
      defaultText = lib.literalExpression ''"''${config.appliance.ca.dir}/ca.crt"'';
      description = "PEM certificate of the appliance CA (mode 0644). Other modules reference this path.";
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dir}/ca.key";
      defaultText = lib.literalExpression ''"''${config.appliance.ca.dir}/ca.key"'';
      description = "PEM private key of the appliance CA (mode 0600, root). Never leaves the host except via the install-time cloud-init channel.";
    };

    commonName = lib.mkOption {
      type = lib.types.str;
      default = "DAWO appliance local CA";
      description = "Subject CN of the CA; also the NSS nickname used for the Chromium import.";
    };

    validityDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3650;
      description = "Validity of the CA certificate in days (default ten years).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dir} 0755 root root -"
    ];

    systemd.services.dawo-appliance-ca = {
      description = "Generate the per-install DAWO appliance CA (once)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      # Browsers must find the CA at the first login; guest/cluster units order
      # themselves after this unit explicitly.
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = generate;
      };
      path = [ pkgs.openssl pkgs.coreutils ];
    };

    # Firefox: merges with upstream's policy set (attrset merge; upstream
    # DAWO-Core 0.1.3 defines no `Certificates` policy).
    programs.firefox.policies.Certificates.Install = [ cfg.certFile ];

    # Chromium: import into the logged-in user's NSS database at every login.
    # `default.target` of the user manager is reached for every graphical and
    # loginctl session; the script is idempotent and tolerates a missing CA.
    systemd.user.services.dawo-appliance-ca-nss = {
      description = "Trust the DAWO appliance CA in this user's NSS database (Chromium)";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = nssImport;
      };
      path = [ pkgs.nssTools pkgs.openssl pkgs.coreutils pkgs.diffutils ];
    };

    # For the appliance's own scripts: `. /etc/dawo-appliance/ca.env` and then
    # `curl --cacert "$DAWO_APPLIANCE_CA_CERT" ...`. The system bundle is not
    # touched at run time.
    environment.etc."dawo-appliance/ca.env".text = ''
      # DAWO appliance CA (hosts/appliance/appliance-ca.nix, ADR 0004).
      # Source this file; the files exist after dawo-appliance-ca.service ran.
      DAWO_APPLIANCE_CA_DIR=${cfg.dir}
      DAWO_APPLIANCE_CA_CERT=${cfg.certFile}
      DAWO_APPLIANCE_CA_KEY=${cfg.keyFile}
      DAWO_APPLIANCE_CA_SHA256=${cfg.certFile}.sha256
      DAWO_APPLIANCE_CA_NICKNAME=${nick}
    '';

    # `certutil` on the PATH for operators and the boot test (small).
    environment.systemPackages = [ pkgs.nssTools ];
  };
}
