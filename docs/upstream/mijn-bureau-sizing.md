# Mijn Bureau sizing: a laptop-demo profile (#11)

Research record, checked **2026-09-25** against mijn-bureau-infra rev
`b2ae545013c153b9a3fb0aebcb51d22f348e1573`. Question: upstream's single-VPS guide
asks for **>= 12 vCPU / >= 48 GiB**; the reference laptop (Dell Latitude 5550,
i5-1345U, 12 threads, 32 GB, also hosting the DAWO Plasma desktop) has less.
What is realistically possible?

Markers: **M** measured, **P** predicted (rendered requests/limits), **G** guessed.

## 1. Findings

1. **The 48 GiB is an empirical recommendation, not a sum of requests.**
   `scripts/single-vps-deploy/01-deploy.sh` sets `resourcesPreset: "none"` for
   every app ("drops resource requests so the suite fits one box"), so the
   rendered manifests carry no requests or limits at all (P: 0 m / 0 MiB). The
   guide was tested on a Hetzner AX41 with 64 GB.
2. **Two knobs:** `global.resourcesPreset` (Bitnami table: nano 100m/128Mi
   request, 150m/192Mi limit; micro 250m/256Mi, 375m/384Mi; small 500m/512Mi,
   750m/768Mi; medium 500m/1Gi, 750m/1.5Gi; large 1/2Gi, 1.5/3Gi) and
   `global.resourcesPresetPerApp`, which **wins** over the global value. The
   default per-app map pins Nextcloud `medium`, Synapse `large`, LiveKit
   `medium`, Docs/Meet/Bureaublad backends `micro`; so lowering only the global
   preset shrinks the sidecars (PostgreSQL, Redis, MinIO, nginx) and leaves the
   heavy apps at upstream's own sizing.
3. **Chart floors:** Keycloak (1 CPU / 1280 Mi request, 2 / 2 Gi limit) and
   Collabora (1 / 512 Mi, 2 / 1 Gi) use the same values for every preset except
   `none` (`charts/keycloak/templates/_keycloak_resources.tpl`,
   `charts/collabora/templates/_collabora_resources.tpl`).
4. **Default app set at rev `b2ae545`:** Keycloak, Element/Synapse, Collabora,
   LiveKit, Meet, Conversations, Docs, Drive, Bureaublad, Ollama, ClamAV on;
   Nextcloud, Grist, OpenProject off. `01-deploy.sh` turns ClamAV, OpenProject
   and Ollama off but does **not** set `nextcloud`/`grist` `enabled: true`,
   although the guide lists both. Uncertain (upstream inconsistency); we must
   enable them explicitly.
5. `predicted_resources.py` sums only Deployment/StatefulSet/DaemonSet
   containers (+ Jobs separately); init containers, cert-manager, K3s system
   pods and the OS are not in it.

## 2. Predicted cluster totals (`predicted_resources.py`)

Rendered with `helmfile 1.1.7` / `helm 3.18.4` against the `demo` environment,
one values file per scenario (apps not listed are `enabled: false`). Core =
Keycloak, Bureaublad, Nextcloud, Collabora, Element/Synapse. Plus = core +
Docs, Grist, Meet, LiveKit. "Global" = `global.resourcesPreset`; "per-app"
= upstream default map, or the same preset forced for every app.

| Scenario | Apps | Global | Per-app | CPU req / lim | Mem req / lim (GiB) | Jobs mem req / lim |
| --- | --- | --- | --- | --- | --- | --- |
| upstream default env | default set (4.) | small | upstream | 19.75 / 32.1 | 29.1 / 43.6 | 4.3 / 7.5 |
| guide app set, presets | Plus | small | upstream | 17.4 / 27.1 | 19.3 / 29.3 | 3.5 / 5.8 |
| guide app set, as `01-deploy.sh` | Plus | none | none | 0 / 0 | 0 / 0 | 0 / 0 |
| core, upstream sizing | core | small | upstream | 7.95 / 12.9 | 9.3 / 14.3 | 1.3 / 2.0 |
| **core, laptop-demo** | core | micro | upstream | **5.95 / 9.9** | **7.25 / 11.25** | 1.0 / 1.6 |
| core, all micro | core | micro | micro | 5.25 / 8.9 | 5.0 / 7.9 | 0.75 / 1.25 |
| core, all nano | core | nano | nano | 3.3 / 5.95 | 3.4 / 5.4 | 0.5 / 0.9 |
| **plus, laptop-demo-plus** | Plus | nano | upstream | **8.6 / 13.9** | **11.0 / 16.9** | 2.4 / 4.1 |
| plus, global micro | Plus | micro | upstream | 11.9 / 18.85 | 13.75 / 21.0 | 2.75 / 4.6 |
| plus, all nano | Plus | nano | nano | 5.6 / 9.4 | 6.25 / 9.75 | 1.75 / 3.1 |

All rows P. The "all nano/micro" rows put Nextcloud and Synapse at a 192-384 Mi
memory limit, far below upstream's 1.5 / 3 Gi; they would likely be OOM-killed
under use (G), so they are shown as a lower bound only. Largest core consumers
(laptop-demo): Synapse 2 Gi req / 3 Gi lim, Keycloak 1.25 / 2 Gi, Nextcloud
1 / 1.5 Gi, Collabora 0.5 / 1 Gi, Nextcloud MinIO (2 pods) 0.5 / 0.75 Gi.

Raw output of the unmodified script (the mixed-preset rows come from a helper
that calls its own `calculate_predicted_resources` per release; totals match):

```text
default demo env: CPU 19750m/32125m  Mem 29824/44608 MiB  (jobs 2900m/4800m, 4352/7680 MiB)
core, all micro:  CPU 5250m/8875m    Mem 5120/8064 MiB    (jobs 600m/950m, 768/1280 MiB)
plus, all nano:   CPU 5600m/9400m    Mem 6400/9984 MiB    (jobs 1000m/1700m, 1792/3200 MiB)
```

## 3. Guest and host overhead

| Item | Memory | CPU | Kind | Source |
| --- | --- | --- | --- | --- |
| K3s server + bundled system pods, single node with a workload | ~1.6 GB (1596 M, p95) | 6 % of a core | M (upstream) | <https://docs.k3s.io/reference/resource-profiling> |
| K3s server minimum | 2 GB | 2 cores | documented | <https://docs.k3s.io/installation/requirements> |
| Ubuntu 24.04 cloud image minimum | 1 GB (3 GB suggested) | - | documented | <https://ubuntu.com/server/docs/reference/installation/system-requirements/> |
| cert-manager (3 pods) + Traefik | ~0.3-0.5 GiB | ~0.2 req | G | - |
| Host: NixOS + DAWO Plasma 6, idle | boots to Plasma + welcome dialog in a 4 GiB test VM | 4 vCPU | M (boots, not RSS) | `test-appliance-boot`, `docs/verification-latest.md` |
| Host: Plasma + Firefox with the suite open + libvirt/QEMU overhead | ~6-8 GiB working reserve | 2-4 threads | G | - |

## 4. Profiles

| Profile | Apps on | Preset (global / per-app) | Guest vCPU / RAM | Host | Basis |
| --- | --- | --- | --- | --- | --- |
| `full` (upstream) | Keycloak, Bureaublad, Nextcloud, Collabora, Element/Synapse, Docs, Grist, Meet+LiveKit | none / none (as `01-deploy.sh`) | 12 / 48 GiB | >= 16 threads / 56 GiB (current manifest) | upstream guide |
| **`laptop-demo`** (recommended default for the 32 GB laptop) | Keycloak, Bureaublad, Nextcloud, Collabora, Element/Synapse | micro / upstream map | **8 / 16 GiB** | 12 threads / 32 GB | P + G |
| `laptop-demo-plus` (optional) | laptop-demo + Docs, Grist, Meet+LiveKit | nano / upstream map | 10 / 22 GiB | 12 threads / 32 GB, tight | P + G |

Off in every profile: ClamAV, OpenProject, Ollama, Conversations, Drive (as in
the upstream single-VPS path, which also does not expose Conversations/Drive).

**laptop-demo budget.** Guest RAM: limits 11.25 GiB (P; limits cap each pod,
so this is an upper bound for the permanent workloads) + install-time Jobs
peak 1.6 GiB (P, transient) + K3s ~1.6 GB (M) + Ubuntu ~1 GiB (documented) +
cert-manager/Traefik ~0.5 GiB (G) = ~15.9 GiB worst case, ~11.5 GiB expected at
requests. CPU requests 5.95 + Jobs 0.85 + system ~0.2 = ~7.0 < 8 vCPU, so every
pod schedules. Host keeps 16 GiB and 4 threads for Plasma and the browser.
Under WSL (24 GB) the same guest leaves ~8 GiB for WSL itself: workable for a
dev run, not a demo.

**laptop-demo-plus budget.** Limits 16.9 + Jobs 4.1 + ~3.1 overhead = ~24 GiB
worst case if every Job ran concurrently, ~14 GiB at requests; 22 GiB guest
leaves 10 GiB to the host (G: tight while the browser runs Meet). CPU requests
8.6 + 1.7 + 0.2 exceed 8 vCPU, hence 10 vCPU (overcommitting the 12 host
threads; acceptable for a mostly idle demo, G). Nano limits (192 Mi) on
PostgreSQL/Redis/MinIO sidecars are an OOM risk under real use (G).

Why `micro`, not `none`: `none` gives no bound and no evidence of fitting 16
GiB; presets give a checkable limit sum and keep upstream's heavy-app sizing.
Measured usage in Slice 6 may justify `none` (closer to `01-deploy.sh`).

## 5. Proposal: profiles in the manifest (not implemented)

```json
"mijn_bureau": {
  "default_profile": "laptop-demo",
  "profiles": {
    "laptop-demo": {
      "apps": ["keycloak", "bureaublad", "nextcloud", "collabora", "element"],
      "preset": "micro", "preset_per_app": "upstream",
      "vm_vcpu": 8, "vm_ram_gib": 16, "host_min_threads": 12, "host_min_ram_gib": 30
    },
    "full": {
      "apps": ["keycloak", "bureaublad", "nextcloud", "collabora", "element", "docs", "grist", "meet", "livekit"],
      "preset": "none", "preset_per_app": "none",
      "vm_vcpu": 12, "vm_ram_gib": 48, "host_min_threads": 16, "host_min_ram_gib": 56
    }
  }
}
```

Mapping to upstream values (the only mechanism used): `apps` ->
`application.<app>.enabled` (all others `false`); `preset` ->
`global.resourcesPreset`; `preset_per_app: "none"` -> every key of
`global.resourcesPresetPerApp` set to `none` as `01-deploy.sh` does, `upstream`
-> the map left untouched. `vm_*` replace `vm.min_vcpu`/`vm.min_ram_gib`; the
bootstrap picks the largest profile the host fits unless one is named.

## 6. Open / uncertain

- No Mijn Bureau pod has run on the appliance yet: every suite figure is P or G.
- Nextcloud/Grist enablement in `01-deploy.sh` vs the guide (finding 4).
- Meet/LiveKit media over the libvirt NAT network is untested. Deviation: D16.
