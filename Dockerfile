# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1 — fetch the pinned upstream sources.
#
# The previous build ran `git clone --depth 1 ...` against upstream master at
# image-build time. That meant every rebuild silently shipped whatever HEAD
# happened to be, with no way to reproduce an older image or to notice if the
# fetched code had changed under us — and it left git (plus its dependency
# chain) in the shipped image.
#
# Here the exact commit is pinned and every file is checksum-verified, so a
# rebuild is reproducible and a moved tag or tampered response fails the build
# instead of being published. Fetching happens in a throwaway stage, so curl
# and ca-certificates never reach the runtime image.
#
# UPSTREAM_REF and the checksums live in .github/tracked-versions.json and are
# bumped together by .github/workflows/check-upstream.yml.
# ---------------------------------------------------------------------------
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS source

ARG UPSTREAM_REPO=alsmith/multicast-relay
ARG UPSTREAM_REF=461d1c97f3aaf0ab9f8996e1a8f24c6b8204d6b4
ARG RELAY_SHA256=60bc9c3a96d980c0e8df7c677bf6c70dd66bce9276a708f20a8ee074a82af786
ARG SSDPDISCOVER_SHA256=57c0d95dce2675d78f2208c77706a7c045364466491998c1a9e30d07c94ef78d

# The checksum guard below reads `printf ... | sha256sum -c -`. Under plain sh
# only the exit status of the last pipe element counts, so a failing printf
# would be masked. pipefail makes the whole pipeline fail, which is the point
# of having the guard at all.
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# apk versions are deliberately unpinned: patch releases are how Alpine ships
# security fixes, and pinning them means a rebuild keeps reinstalling the
# known-bad build until someone hand-edits this line. The base image *is*
# digest-pinned, so what floats is limited to patched packages within that
# pinned Alpine release.
# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates curl

WORKDIR /out/multicast-relay
RUN set -eux; \
    base="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REF}"; \
    curl -fsSL --retry 3 --max-time 60 "${base}/multicast-relay.py" -o multicast-relay.py; \
    curl -fsSL --retry 3 --max-time 60 "${base}/ssdpDiscover.py"    -o ssdpDiscover.py; \
    printf '%s  %s\n' "${RELAY_SHA256}"         multicast-relay.py | sha256sum -c -; \
    printf '%s  %s\n' "${SSDPDISCOVER_SHA256}"  ssdpDiscover.py    | sha256sum -c -; \
    chmod 0755 multicast-relay.py ssdpDiscover.py

# ---------------------------------------------------------------------------
# Stage 2 — runtime.
# ---------------------------------------------------------------------------
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS runtime

ARG UPSTREAM_REPO=alsmith/multicast-relay
ARG UPSTREAM_REF=461d1c97f3aaf0ab9f8996e1a8f24c6b8204d6b4
# Populated by CI (docker/metadata-action); harmless placeholders for local builds.
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED=1970-01-01T00:00:00Z

LABEL org.opencontainers.image.title="multicast-relay" \
      org.opencontainers.image.description="mDNS/SSDP multicast relay for multi-homed hosts (UniFi Dream Machine and friends)" \
      org.opencontainers.image.source="https://github.com/scyto/multicast-relay" \
      org.opencontainers.image.url="https://github.com/scyto/multicast-relay" \
      org.opencontainers.image.documentation="https://github.com/scyto/multicast-relay#readme" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.base.name="docker.io/library/alpine:3.24.1" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      io.github.scyto.upstream.repo="${UPSTREAM_REPO}" \
      io.github.scyto.upstream.ref="${UPSTREAM_REF}"

# python3 + netifaces are all the relay needs at runtime; tzdata makes $TZ
# resolve so log timestamps are local. `py-netifaces` (used previously) is a
# stale alias — the real package is py3-netifaces.
# hadolint ignore=DL3018
RUN set -eux; \
    apk add --no-cache python3 py3-netifaces tzdata; \
    # Nothing in this image legitimately escalates privilege, so strip every
    # setuid/setgid bit. If the relay is ever compromised it then has no
    # in-image path back to root, which matters because this container is
    # normally run with --network=host.
    find / -xdev -type f -perm /6000 -exec chmod a-s {} + ; \
    rm -rf /var/cache/apk/* /root/.cache

COPY --from=source /out/multicast-relay /multicast-relay
COPY start.sh healthcheck.sh /

# Byte-compile as a build-time smoke test: a source file that upstream broke,
# or a Python version that no longer parses it, fails the build here rather
# than shipping a container that crash-loops on start. Any SyntaxWarning is
# surfaced in the build log, which is where it is actionable.
#
# __pycache__ is then dropped: Python only reads cached bytecode for imported
# modules, never for the top-level script, so it would be dead weight that the
# read-only rootfs has to carry.
RUN set -eux; \
    chmod 0755 /start.sh /healthcheck.sh; \
    python3 -m py_compile /multicast-relay/multicast-relay.py; \
    rm -rf /multicast-relay/__pycache__

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    TZ=America/Los_Angeles \
    INTERFACES="br0 br50" \
    OPTS="" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Upstream's multicast-relay.py has two pre-3.12 regex literals ('\A...')
    # that make modern Python emit SyntaxWarning on every start, burying the
    # relay's actual log output. Silenced at runtime only — the build-time
    # py_compile above still reports them, so a genuinely new syntax problem in
    # a bumped upstream commit is caught in CI rather than hidden.
    PYTHONWARNINGS=ignore::SyntaxWarning

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/healthcheck.sh"]

# Exec form, so start.sh is PID 1 and its `exec python3` inherits PID 1 —
# SIGTERM then reaches the relay directly and `docker stop` is immediate
# instead of waiting out the 10s kill timeout. Kept as CMD rather than
# ENTRYPOINT so `docker run --rm -it <image> sh` still drops you to a shell.
CMD ["/start.sh"]
