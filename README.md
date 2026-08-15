# multicast-relay

[![Build and publish image](https://github.com/scyto/multicast-relay/actions/workflows/build.yml/badge.svg)](https://github.com/scyto/multicast-relay/actions/workflows/build.yml)
[![Lint](https://github.com/scyto/multicast-relay/actions/workflows/lint.yml/badge.svg)](https://github.com/scyto/multicast-relay/actions/workflows/lint.yml)

A container that relays mDNS and SSDP between VLANs, so Chromecasts, Sonos speakers, printers and other discovery-based devices on one network can be found from another.

Originally built for the UniFi Dream Machine, but it works on any multi-homed Linux host.

This packages [alsmith/multicast-relay](https://github.com/alsmith/multicast-relay) — all the relaying logic is theirs. This repository provides the container, the hardening and the build pipeline.

## Quick start

```bash
docker run -d --name ssdp-relay --restart=always \
  --network=host \
  -e INTERFACES="br0 br50" \
  ghcr.io/scyto/multicast-relay
```

`--network=host` is mandatory — the relay has to see the host's bridges. Replace `br0 br50` with your own interfaces; see [finding your interfaces](#finding-your-interfaces) below.

> **UniFi OS users:** current UniFi OS ships Docker, so these commands work as written. Older UniFi OS releases shipped `podman` instead — on those, substitute `podman` for `docker` throughout.

Out of the box this relays:

| Protocol | Address |
|---|---|
| mDNS | `224.0.0.251:5353` |
| SSDP | `239.255.255.250:1900` |
| Sonos discovery | `255.255.255.255:1900` (broadcast) |
| Sonos setup | `255.255.255.255:6969` (broadcast) |

## Where to pull from

Published to **GitHub Container Registry** (primary) and mirrored to **Docker Hub**. Both get every build from the same multi-arch manifest, so the two are byte-identical — if you already pull from Docker Hub, nothing changes for you.

```bash
docker pull ghcr.io/scyto/multicast-relay:latest   # preferred
docker pull scyto/multicast-relay:latest           # still fully supported
```

Platforms: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6`.

### Tags

Tags fall into two groups, and the difference matters if you care about reproducibility.

**Immutable** — published once and never repointed. CI fails the build rather than overwrite one:

| Tag | Meaning |
|---|---|
| `1.2.3` | One exact release. Always the same image. |
| `master-<sha>` | One exact build of one commit on `master`. |

**Moving** — pointers meant to be reassigned:

| Tag | Meaning |
|---|---|
| `latest` | The newest **release**. Only a `v*` git tag moves it; merging to `master` does not. |
| `1.2` / `1` | Newest patch in that series, so you pick up fixes automatically. |
| `edge` | Newest build from `master`. Untested-in-the-wild code — expect it to change under you. |

For a working relay, use `latest`. To know exactly what you are running, pin `1.2.3`, or pin the digest, which survives even tag deletion:

```bash
docker pull ghcr.io/scyto/multicast-relay@sha256:<digest>
```

Every release records its digest in the [release notes](https://github.com/scyto/multicast-relay/releases).

## Configuration

Everything is configured through environment variables.

| Variable | Default | Meaning |
|---|---|---|
| `INTERFACES` | `br0 br50` | **Set this.** Space-separated interfaces to relay between, minimum two. The default assumes LAN on `br0` and an IoT VLAN 50 on `br50`, which is unlikely to match your network. |
| `OPTS` | *(empty)* | Space-separated extra options passed to the relay. See below. |
| `TZ` | `America/Los_Angeles` | Timezone for log timestamps. |
| `K8SPORT` | *(empty)* | If you pass `--k8sport <port>` in `OPTS`, set this to the same port and the healthcheck probes that HTTP endpoint instead of just checking the process is alive. |

On UniFi hardware interfaces are named `brN`, where `N` is the VLAN ID — `br0` is the default LAN (no VLAN / VLAN 1), `br50` is VLAN 50, and so on.

### Finding your interfaces

The image can list them for you:

```bash
docker run --rm --network=host ghcr.io/scyto/multicast-relay ls /sys/class/net
```

If you name an interface that does not exist, the container exits immediately and prints the ones it can see, so a typo is self-diagnosing.

### Relay options

Set these via `OPTS`, e.g. `-e OPTS="--verbose --noMDNS"`.

Commonly used:

| Option | Effect |
|---|---|
| `--verbose` | Log every relayed packet. The first thing to turn on when something is not working. |
| `--noMDNS` | Do not relay mDNS. Use this if your router already has its own mDNS reflector enabled, to avoid duplicate relaying. |
| `--noSSDP` | Do not relay SSDP. |
| `--noSonosDiscovery` | Do not relay the broadcast Sonos discovery packets (udp/1900 and udp/6969). |
| `--ttl N` | Set the TTL on outbound packets. Occasionally needed for devices that drop low-TTL traffic. |
| `--relay ADDR:PORT` | Relay an additional multicast address, for protocols not handled by default. |
| `--noTransmitInterfaces IF` | Listen on these interfaces but never transmit to them — useful for a one-way relay. |
| `--ifFilter FILE.json` | Restrict which interfaces a given source IP may relay to. Requires mounting the JSON file into the container. |
| `--k8sport N` | Run an HTTP liveness endpoint on this port. Pair with the `K8SPORT` variable above. |

Also available: `--oneInterface`, `--mdnsForceUnicast`, `--ssdpUnicastAddr`, `--masquerade`, `--wait`, `--allowNonEther`, `--homebrewNetifaces`, `--ifNameStructLen`, and the remote-relay set (`--listen`, `--remote`, `--remotePort`, `--remoteRetry`, `--noRemoteRelay`, `--aes`) for linking relays across sites.

For the authoritative list:

```bash
docker run --rm ghcr.io/scyto/multicast-relay \
  python3 /multicast-relay/multicast-relay.py --help
```

Two notes:

- `--foreground` is applied automatically by the entrypoint. You do not need to add it.
- `--logfile` writes to disk, which fails under the recommended `--read-only` flag unless you mount a writable volume for it. Container logs (`docker logs`) are usually what you want instead.

## Examples

**Several VLANs, SSDP only** — relay between LAN, VLAN 50 and VLAN 60, letting the router handle mDNS itself:

```bash
docker run -d --name ssdp-relay --restart=always --network=host \
  -e INTERFACES="br0 br50 br60" \
  -e OPTS="--verbose --noMDNS" \
  ghcr.io/scyto/multicast-relay
```

**LAN as a management VLAN** — where every network is a numbered VLAN:

```bash
docker run -d --name ssdp-relay --restart=always --network=host \
  -e INTERFACES="br10 br75 br90" \
  ghcr.io/scyto/multicast-relay
```

**Watch it work** — run in the foreground with verbose logging, and stop with Ctrl-C:

```bash
docker run --rm -it --network=host \
  -e INTERFACES="br0 br50" -e OPTS="--verbose" \
  ghcr.io/scyto/multicast-relay
```

### Recommended hardened invocation

The relay needs `--network=host` and exactly one Linux capability, `CAP_NET_RAW`, to open the raw sockets it relays with. It needs nothing else, so take everything else away:

```bash
docker run -d --name ssdp-relay --restart=always \
  --network=host \
  --cap-drop=ALL --cap-add=NET_RAW \
  --security-opt no-new-privileges \
  --read-only --tmpfs /tmp \
  -e INTERFACES="br0 br50" \
  ghcr.io/scyto/multicast-relay
```

This exact configuration is verified in CI on every build, so it is supported rather than merely suggested. `--cap-drop=ALL --cap-add=NET_RAW` takes the container from the ~14 capabilities Docker grants by default down to one.

### Docker Compose

```yaml
services:
  multicast-relay:
    image: ghcr.io/scyto/multicast-relay:latest
    container_name: ssdp-relay
    restart: always
    network_mode: host
    cap_drop: [ALL]
    cap_add: [NET_RAW]
    security_opt: [no-new-privileges:true]
    read_only: true
    tmpfs: [/tmp]
    environment:
      INTERFACES: "br0 br50"
      OPTS: ""
      TZ: "Europe/London"
```

## Upgrading

```bash
docker pull ghcr.io/scyto/multicast-relay:latest
docker stop ssdp-relay && docker rm ssdp-relay
# then re-run your original docker run command
```

With Compose: `docker compose pull && docker compose up -d`.

There is no state to preserve — the relay keeps nothing on disk.

## Troubleshooting

**`ERROR: interface(s) not visible to this container`** — the container prints the interfaces it *can* see. This nearly always means `--network=host` was omitted, or an interface name is wrong.

**Devices still do not appear.** Work through it in this order:

1. Run with `-e OPTS="--verbose"` and watch `docker logs -f ssdp-relay`. If you see packets being relayed, the relay is doing its job and the problem is elsewhere on the network.
2. Check firewall rules between the VLANs — see below.
3. If your router has its own mDNS reflector enabled, run with `--noMDNS` so the two are not both relaying.
4. Confirm the device actually uses mDNS or SSDP. Some discovery protocols use neither, and `--relay` may be needed for those.

**Is it healthy?** `docker ps` shows a health column for this image, or query it directly:

```bash
docker inspect -f '{{.State.Health.Status}}' ssdp-relay
```

**It will not stop cleanly.** It should stop in about a second. If `docker stop` takes 10 seconds you are running an old image — pull again.

## Firewall notes

Discovery is only half the problem. Once devices have found each other they open ordinary unicast connections, and those must be permitted too. With Sonos, for example, the speakers connect *back* to the phone running the controller app, so traffic from the Sonos VLAN to the client VLAN has to be allowed.

On a Linux host that filters multicast on input, you may need:

```bash
sudo iptables -I INPUT -m pkttype --pkt-type multicast -j ACCEPT
```

Remember to persist iptables rules once everything works, or they vanish on reboot.

## Security

- **Pinned, verified upstream.** The relay source is pinned to an exact upstream commit and every file is SHA256-verified at build time. The image previously ran `git clone` against upstream `master` during the build, so each rebuild shipped whatever HEAD happened to be, with no way to reproduce an earlier image. A daily workflow proposes pin bumps as reviewable pull requests, so the pin stays current without the build being unpredictable.
- **Digest-pinned base image.** Alpine is pinned by digest, not just tag.
- **Minimal runtime.** A multi-stage build keeps `git`, `curl` and `ca-certificates` out of the shipped image; only `python3`, `py3-netifaces`, `tzdata` and `tini` remain. CI fails the build if a build tool reappears in the runtime image.
- **No setuid binaries.** Every setuid/setgid bit is stripped and CI asserts none come back — which matters because this container runs in the host network namespace.
- **Runs on one capability.** Verified in CI with `--cap-drop=ALL --cap-add=NET_RAW`, `no-new-privileges` and a read-only root filesystem.
- **Immutable release tags.** Neither registry enforces tag immutability on these plans, so CI does: a build that would overwrite an existing `X.Y.Z` or `master-<sha>` tag fails before pushing. What `1.2.3` means cannot change after the fact.
- **Vulnerability scanned.** Every build is scanned with Trivy and fails on fixable HIGH/CRITICAL findings.
- **Protected default branch.** `master` requires a pull request, blocks force-pushes and deletion, and requires CI to pass, so nothing reaches a published image unchecked.
- **Dependency updates.** Dependabot raises weekly PRs for GitHub Actions and the pinned Alpine base, so digest pinning cannot quietly become staying unpatched.
- **Signed provenance and SBOM.** Images ship an SBOM and a SLSA build provenance attestation:
  ```bash
  gh attestation verify oci://ghcr.io/scyto/multicast-relay:latest --repo scyto/multicast-relay
  ```
- **Correct signal handling.** `tini` runs as PID 1 and forwards SIGTERM to the relay, so `docker stop` is immediate rather than waiting out the 10s timeout and SIGKILLing. The kernel discards default-disposition signals aimed at PID 1 and `multicast-relay.py` installs no SIGTERM handler, so without an init process the relay simply ignores SIGTERM. CI asserts the container exits 143, not 137.

## Building and CI

| Workflow | Trigger | Does |
|---|---|---|
| [`build.yml`](.github/workflows/build.yml) | push to `master`, `v*.*.*` tags, PRs, manual | Builds, smoke-tests, scans, then publishes the multi-arch image to GHCR and Docker Hub. PRs build and test but never push. |
| [`lint.yml`](.github/workflows/lint.yml) | push / PR touching build files | hadolint, shellcheck, actionlint, and a check that `tracked-versions.json` agrees with the Dockerfile. |
| [`check-upstream.yml`](.github/workflows/check-upstream.yml) | daily 06:00 UTC, manual | Polls upstream for new commits; re-pins, recomputes checksums and opens a PR with the bump for review. Merging it moves `:edge` only, never `:latest`. |

The smoke test does more than start the container. It asserts all four relays come up, that effective capabilities are exactly `CAP_NET_RAW`, that `tini` is PID 1 with the relay as its child, that the healthcheck passes, that no setuid binaries or build tools survive in the image, and that the container exits 143 (SIGTERM honoured) rather than 137 (SIGKILL after timeout).

### Cutting a release

`master` builds only ever move `:edge`. To publish a release and move `:latest`:

```bash
git tag v1.2.3 && git push origin v1.2.3
```

That publishes `:1.2.3`, `:1.2`, `:1` and `:latest`, then creates a GitHub release recording the image digest. Re-tagging an already published version is refused by the immutability check — cut a new patch version instead.

### What is pinned

[`.github/tracked-versions.json`](.github/tracked-versions.json) is the single source of truth for the upstream commit, its file checksums and the Alpine base digest. The Dockerfile's `ARG` defaults mirror it, so a plain local `docker build` with no arguments produces the same image CI does; `lint.yml` fails if the two drift.

### Building locally

```bash
docker build -t multicast-relay:local .
```

To check a change still builds for every published platform, without pushing:

```bash
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6 \
  --output type=cacheonly .
```

Publishing is CI's job — a hand-pushed `:latest` would bypass the smoke test and vulnerability scan and overwrite a verified image with an unverified one.

### Repository secrets

Docker Hub mirroring requires two repository secrets:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token with **Read & Write** scope |

Without them the build still succeeds and publishes to GHCR, logging a warning that Docker Hub was skipped. GHCR needs no secrets — the built-in `GITHUB_TOKEN` covers it.

## Credits and licence

The relay itself is [alsmith/multicast-relay](https://github.com/alsmith/multicast-relay) by Al Smith. This repository packages it as a container; the heavy lifting is upstream's.

Two licences apply, because the image combines two works:

| Part | Licence |
|---|---|
| This repository — Dockerfile, entrypoint, healthcheck, CI, docs | [MIT](LICENSE) |
| `multicast-relay.py` and `ssdpDiscover.py`, fetched at build time | [GPL-3.0](https://github.com/alsmith/multicast-relay/blob/master/LICENSE) |

The published image therefore contains GPL-3.0 code and is labelled `MIT AND GPL-3.0-only`. If you redistribute the image, the GPL's terms apply to the relay it contains.
