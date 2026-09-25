# Slice 4b — per-install appliance CA (hosts/appliance/appliance-ca.nix, ADR 0004).
#
# Assertions for the `test-appliance-boot` testScript in flake.nix. Plain text:
# paste the two blocks into the testScript at the marked places (the file is
# not imported by Nix). Requirements R20–R22 in docs/testing.md.

# ---- Block A: paste after `machine.wait_for_unit("multi-user.target")` ------

# R20: the CA service ran once at first boot and produced the contract files.
machine.wait_for_unit("dawo-appliance-ca.service")
machine.succeed("systemctl is-active dawo-appliance-ca.service")   # RemainAfterExit
ca_dir = "/var/lib/dawo-appliance/ca"
machine.succeed(f"test -s {ca_dir}/ca.crt && test -s {ca_dir}/ca.key && test -s {ca_dir}/ca.crt.sha256")
machine.succeed(f"test \"$(stat -c %a {ca_dir}/ca.key)\" = 600")
machine.succeed(f"test \"$(stat -c %U:%G {ca_dir}/ca.key)\" = root:root")
machine.succeed(f"test \"$(stat -c %a {ca_dir}/ca.crt)\" = 644")
machine.succeed(f"cd {ca_dir} && sha256sum -c ca.crt.sha256")
x509 = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -text")
assert "CA:TRUE" in x509, "appliance CA lacks basicConstraints CA:TRUE"
assert "Certificate Sign" in x509 and "CRL Sign" in x509, "appliance CA lacks keyCertSign/cRLSign"
assert "CN=DAWO appliance local CA" in x509 or "CN = DAWO appliance local CA" in x509, "unexpected CA subject"
machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -checkend 86400")   # not about to expire
# The key matches the certificate (same public key).
machine.succeed(
    f"test \"$(openssl x509 -in {ca_dir}/ca.crt -noout -pubkey | sha256sum)\" = "
    f"\"$(openssl pkey -in {ca_dir}/ca.key -pubout | sha256sum)\"")
# Idempotent: a second start keeps the same certificate.
fp_before = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -fingerprint -sha256").strip()
machine.succeed("systemctl restart dawo-appliance-ca.service")
fp_after = machine.succeed(f"openssl x509 -in {ca_dir}/ca.crt -noout -fingerprint -sha256").strip()
assert fp_before == fp_after, "dawo-appliance-ca.service regenerated an existing CA"
# The key is unreadable for the desktop user; the certificate is readable.
machine.fail(f"su -s /bin/sh dawo -c 'cat {ca_dir}/ca.key'")
machine.succeed(f"su -s /bin/sh dawo -c 'test -r {ca_dir}/ca.crt'")
# CLI trust: the env file names the files.
machine.succeed(f"grep -qx 'DAWO_APPLIANCE_CA_CERT={ca_dir}/ca.crt' /etc/dawo-appliance/ca.env")

# R21: Firefox trusts the CA via the merged enterprise policy (nixpkgs writes
# `programs.firefox.policies` to /etc/firefox/policies/policies.json); upstream's
# own policies must still be there (attrset merge, no override).
policies = machine.succeed("cat /etc/firefox/policies/policies.json")
assert f"{ca_dir}/ca.crt" in policies, "Firefox policies.json does not install the appliance CA"
machine.succeed(
    "python3 -c \"import json,sys; p=json.load(open('/etc/firefox/policies/policies.json'))['policies']; "
    f"assert p['Certificates']['Install']==['{ca_dir}/ca.crt'], p.get('Certificates'); "
    "assert p['DisableTelemetry'] is True and 'plasma-browser-integration@kde.org' in p['ExtensionSettings']\"")

# ---- Block B: paste after `machine.wait_until_succeeds("pgrep -u dawo -f plasmashell", ...)` ----

# R22: Chromium/NSS — the per-login user service imported the CA into the
# dawo user's NSS database (idempotent; re-run leaves one entry).
machine.wait_until_succeeds(
    "systemctl --user -M dawo@ is-active dawo-appliance-ca-nss.service", timeout=120)
nss_list = machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L")
assert "DAWO appliance local CA" in nss_list, "appliance CA not in dawo's NSS database: " + nss_list
assert nss_list.count("DAWO appliance local CA") == 1, "duplicate CA entries in NSS db"
# Trusted as a CA for TLS server authentication (trust flags "C,,").
machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L | grep 'DAWO appliance local CA' | grep -q 'C,,'")
# Same certificate as on disk.
machine.succeed(
    "test \"$(certutil -d sql:/home/dawo/.pki/nssdb -L -n 'DAWO appliance local CA' -r | sha256sum)\" = "
    f"\"$(openssl x509 -in {ca_dir}/ca.crt -outform DER | sha256sum)\"")
machine.succeed("systemctl --user -M dawo@ restart dawo-appliance-ca-nss.service")
assert machine.succeed("certutil -d sql:/home/dawo/.pki/nssdb -L").count("DAWO appliance local CA") == 1
