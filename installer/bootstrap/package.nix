# Wrapped `dawo-appliance-bootstrap`: the script plus its runtime dependencies
# on PATH. Defined once here and consumed by the flake (as a package) and by the
# live-system payload (installer/live-payload.nix), so there is a single source
# of truth for how the command is built.
{ lib, runCommand, makeWrapper, bash, coreutils, curl, jq, gnused, gawk }:

runCommand "dawo-appliance-bootstrap"
  { nativeBuildInputs = [ makeWrapper ]; }
  ''
    mkdir -p $out/bin
    cp ${./dawo-appliance-bootstrap} $out/bin/dawo-appliance-bootstrap
    chmod +x $out/bin/dawo-appliance-bootstrap
    wrapProgram $out/bin/dawo-appliance-bootstrap \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils curl jq gnused gawk ]}
  ''
