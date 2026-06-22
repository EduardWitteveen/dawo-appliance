# Health checks

Local health check that gates the final browser-open step (Slice 7).

Planned: wait until the deployment is healthy, mirroring upstream's documented
checks — `kubectl get certificate -A` until all are Ready, then an HTTP(S)
readiness probe against the dashboard `https://bureaublad.<base_domain>`. Only
once healthy does the appliance open the dashboard in the browser.

Not implemented yet.
