#!/bin/sh
#
# Container entrypoint for multicast-relay.
#
# Launched by tini (PID 1). The `exec` below matters: it replaces this shell
# with python so the relay becomes tini's direct child, which is what lets tini
# forward SIGTERM to it. Leave the shell in place and it sits between the two,
# swallowing the signal, and every `docker stop` waits out the full timeout and
# ends in a SIGKILL.
set -eu

if [ -z "${INTERFACES:-}" ]; then
    echo "ERROR: INTERFACES is empty. Set it to a space-separated interface list," >&2
    echo "       e.g. -e INTERFACES=\"br0 br50\"" >&2
    exit 1
fi

# Fail early and legibly when an interface does not exist in this container's
# network namespace. The relay's own error for a missing interface is a bare
# netifaces traceback, which reads like a crash rather than a config mistake —
# and the usual cause is simply forgetting --network=host.
missing=""
for iface in ${INTERFACES}; do
    [ -e "/sys/class/net/${iface}" ] || missing="${missing} ${iface}"
done
if [ -n "${missing}" ]; then
    echo "ERROR: interface(s) not visible to this container:${missing}" >&2
    echo "       Available: $(ls /sys/class/net | tr '\n' ' ')" >&2
    echo "       This container needs --network=host to see the host's bridges." >&2
    exit 1
fi

echo "starting multicast-relay"
echo "Using Interfaces: ${INTERFACES}"
echo "Using Options --foreground ${OPTS:-}"

# INTERFACES and OPTS are intentionally word-split: both are space-separated
# lists of separate argv entries, which is the documented interface for this
# image and what existing users' `docker run` lines rely on.
# shellcheck disable=SC2086
exec python3 /multicast-relay/multicast-relay.py \
    --interfaces ${INTERFACES} \
    --foreground ${OPTS:-}
