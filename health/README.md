# Health checks (Slice 7, not implemented yet)

Local health check that gates the final browser-open step.

Planned: wait until the deployment is healthy, mirroring upstream's documented
checks (`kubectl get certificate -A` until all are Ready, then an HTTP(S)
readiness probe against the dashboard `https://bureaublad.<base-domain>`). Only
once healthy does the appliance open the dashboard in the browser, from the
same login hook as the welcome dialog (`hosts/appliance/appliance-services.nix`).
