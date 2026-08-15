# multicast-relay docker for Unifi Dream Machine

[![Build and publish image](https://github.com/scyto/multicast-relay/actions/workflows/build.yml/badge.svg)](https://github.com/scyto/multicast-relay/actions/workflows/build.yml)
[![Lint](https://github.com/scyto/multicast-relay/actions/workflows/lint.yml/badge.svg)](https://github.com/scyto/multicast-relay/actions/workflows/lint.yml)

This is a docker container that implements <https://github.com/alsmith/multicast-relay> to provide mDNS and SSDP on a unifi dream machine. It will likely work on any multi homed host.

## Where to pull from

The image is published to **GitHub Container Registry** (primary) and mirrored to **Docker Hub**. Both registries receive every build, from the same multi-arch manifest — if you are already pulling from Docker Hub, nothing you are doing breaks.

```bash
# Preferred
docker pull ghcr.io/scyto/multicast-relay:latest

# Still fully supported
docker pull scyto/multicast-relay:latest
```

### Tags

| Tag | Meaning |
|---|---|
| `latest` | Newest build from `master`. What you get if you don't specify a tag. |
| `1.2.3`, `1.2`, `1` | Released versions, from a `v1.2.3` git tag. Use these if you want to pin. |
| `master-<sha>` | One exact build from `master`, for pinning to a known-good image. |

Platforms: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6`.

## Required Environment Variables

To run this container you will need to define the following variables:

| Environment Variable | Default | Explanation |
|----------------------|---------|-------------|
| INTERFACES | br0 br50 | Space separated list of interfaces. br0 is required for LAN, all other interfaces will be in the format brN where n is the number of the vlan. This image defaults to vlan50 for the IoT network and assumes your main private network is LAN. This can be overridden - see below. |
| OPTS | | Space separated list of additional command line options, none specified by default, examples below: |
| | | `--verbose` (if you want verbose logging) |
| | | `--noMDNS` (disables mDNS relaying, e.g. if you are using the unifi one disable this) |
| | | `--noSSDP` disables SSDP relaying. (disables SSDP, but not sure why you would want to) |
| | | `--noSonosDiscovery` (disables broadcast udp/6969 relaying) |
| | | for full list of options see <https://github.com/alsmith/multicast-relay> |
| TZ | America/Los_Angeles | Timezone used for log timestamps. |
| K8SPORT | | Optional. If you run the relay with `--k8sport <port>`, set this to the same port and the container healthcheck will probe that HTTP endpoint instead of just checking the process is alive. |

To override OPTS use the docker run option `-e OPTS="your options"` or `-e OPTS=""`.

## Getting Running

**NOTE if you are running this on unifios you will need to use the podman command instead of the docker command**

To get started this is the minimum number of options. This assumes your LAN is BR0 (VLAN null / 1) and your IoT network is VLAN #50:

```bash
docker run --network=host --restart=always --name ssdp-relay ghcr.io/scyto/multicast-relay
```

For testing use this to see console output:

```bash
docker run --rm -it --network=host -e OPTS="--verbose" -e INTERFACES="br0 br50" ghcr.io/scyto/multicast-relay
```

### Recommended hardened invocation

The relay needs `--network=host` to see your bridges, and one Linux capability (`CAP_NET_RAW`) to open the raw sockets it relays with. It needs nothing else — so take everything else away:

```bash
docker run -d --name ssdp-relay --restart=always \
  --network=host \
  --cap-drop=ALL --cap-add=NET_RAW \
  --security-opt no-new-privileges \
  --read-only --tmpfs /tmp \
  -e INTERFACES="br0 br50" \
  ghcr.io/scyto/multicast-relay
```

This is verified in CI on every build, so it is a supported configuration rather than a suggestion. `--cap-drop=ALL --cap-add=NET_RAW` reduces the container from the ~14 capabilities Docker grants by default to exactly one.

## More than LAN and 1 VLAN

To run on multiple vlans and have more detailed info and turn off mDNS so you can use the unifi provided one. For example this forwards just SSDP but not mDNS between LAN, VLAN50 and VLAN60:

```bash
docker run --network=host --name ssdp-relay --restart=always -e INTERFACES="br0 br50 br60" -e OPTS="--verbose --noMDNS" ghcr.io/scyto/multicast-relay
```

If you use LAN as your management VLAN (aka no VLAN / VLAN1) then your command needs to look something like this where N is each VLAN number:

```bash
docker run --network=host --name ssdp-relay --restart=always -e INTERFACES="br10 br75 br90 [etc] " ghcr.io/scyto/multicast-relay
```

## Firewall Notes

Please note that even when your devices have discovered one another, at least in the Sonos case, a unicast connection will be established from the speakers back to the controlling client running the Sonos app. You will need to make sure that no firewalling is in place that would prevent connections being established from the SONOS VLAN to the client device VLAN.

E.G. To allow chromecast through the firewall on a vm (photon 4), do not forget to save iptables after everything is working:

```bash
sudo iptables -I INPUT -m pkttype --pkt-type multicast -j ACCEPT
```

## Troubleshooting

**`ERROR: interface(s) not visible to this container`** — the container lists the interfaces it *can* see. Almost always this means `--network=host` was omitted, or an interface name has a typo. The container exits immediately rather than looping on a traceback.

**Checking it is healthy** — `docker ps` shows a health status for this image. `docker inspect -f '{{.State.Health.Status}}' ssdp-relay` reports it directly.

## Security

- **Pinned, verified upstream.** The relay source is pinned to an exact upstream commit and every file is SHA256-verified at build time. Previously the image ran `git clone` against upstream `master` during the build, so each rebuild shipped whatever HEAD happened to be, with no way to reproduce an earlier image. A daily workflow bumps the pin deliberately, so the pin stays current without the build being unpredictable.
- **Digest-pinned base image.** Alpine is pinned by digest, not just tag.
- **Minimal runtime.** A multi-stage build keeps `git`, `curl` and `ca-certificates` out of the shipped image; only `python3`, `py3-netifaces` and `tzdata` remain. CI fails the build if a build tool reappears in the runtime image.
- **No setuid binaries.** Every setuid/setgid bit is stripped, and CI asserts none come back. This matters because the container runs on the host network namespace.
- **Runs on one capability.** Verified in CI to work with `--cap-drop=ALL --cap-add=NET_RAW`, `--security-opt no-new-privileges` and a read-only root filesystem.
- **Vulnerability scanned.** Every build is scanned with Trivy and fails on fixable HIGH/CRITICAL findings.
- **Signed provenance and SBOM.** Images ship an SBOM and SLSA build provenance attestation. Verify a pull with:
  ```bash
  gh attestation verify oci://ghcr.io/scyto/multicast-relay:latest --repo scyto/multicast-relay
  ```
- **Correct signal handling.** `tini` runs as PID 1 and forwards SIGTERM to the relay, so `docker stop` terminates it immediately instead of waiting out the 10s timeout and SIGKILLing it. The Linux kernel discards default-disposition signals aimed at PID 1, and `multicast-relay.py` installs no SIGTERM handler, so without an init process the relay simply ignores SIGTERM. CI asserts the container exits 143 (SIGTERM) rather than 137 (SIGKILL).

## Building and CI

Images are built and published by GitHub Actions:

| Workflow | Trigger | Does |
|---|---|---|
| [`build.yml`](.github/workflows/build.yml) | push to `master`, `v*.*.*` tags, PRs, manual | Builds, smoke-tests, scans, then publishes the multi-arch image to GHCR and Docker Hub. PRs build and test but never push. |
| [`lint.yml`](.github/workflows/lint.yml) | push / PR touching build files | hadolint, shellcheck, actionlint, and a check that `tracked-versions.json` agrees with the Dockerfile. |
| [`check-upstream.yml`](.github/workflows/check-upstream.yml) | daily 06:00 UTC, manual | Polls upstream for new commits; re-pins, recomputes checksums, commits and triggers a build. |

The smoke test does not merely start the container — it asserts all four relays come up, that effective capabilities are exactly `CAP_NET_RAW`, that PID 1 is python, that the healthcheck passes, and that SIGTERM is honoured.

### What is pinned

[`.github/tracked-versions.json`](.github/tracked-versions.json) is the single source of truth for the upstream commit, its file checksums, and the Alpine base digest. The Dockerfile's `ARG` defaults mirror it, so a plain local `docker build` with no arguments produces the same image CI does; `lint.yml` fails if the two drift.

### Building locally

```bash
docker build -t multicast-relay:local .
```

To check a Dockerfile change still builds for every published platform before committing, without pushing anything:

```bash
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6 \
  --output type=cacheonly .
```

Publishing is CI's job — a hand-pushed `:latest` would bypass the smoke test and vulnerability scan, and overwrite a verified image with an unverified one.

To bump the upstream pin by hand, edit `tracked-versions.json` and the matching `ARG` defaults, or just run the `check-upstream` workflow.

### Repository secrets

Docker Hub mirroring requires two repository secrets:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username (`scyto`) |
| `DOCKERHUB_TOKEN` | A Docker Hub access token with **Read & Write** scope |

If they are absent the build still succeeds and publishes to GHCR, logging a warning that Docker Hub was skipped. No secrets are needed for GHCR — the built-in `GITHUB_TOKEN` covers it.
