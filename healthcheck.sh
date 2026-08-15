#!/bin/sh
#
# Container healthcheck.
#
# If the relay was started with --k8sport, that HTTP endpoint is the real
# liveness signal and is used. Otherwise fall back to checking the relay
# process is still alive — weaker, but it does catch the case where the relay
# exits while PID 1's supervisor keeps the container nominally "up".
set -eu

port="${K8SPORT:-}"

# --k8sport in OPTS wins over the K8SPORT convenience variable, since that is
# what the relay actually bound.
case " ${OPTS:-} " in
    *" --k8sport "*)
        port=$(printf '%s\n' "${OPTS}" | tr ' ' '\n' | grep -A1 -x -- '--k8sport' | tail -n1)
        ;;
esac

if [ -n "${port}" ]; then
    exec wget -q -T 4 -O /dev/null "http://127.0.0.1:${port}/"
fi

pgrep -f 'multicast-relay\.py' >/dev/null 2>&1
