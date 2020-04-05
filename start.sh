#!/bin/ash
echo "starting multicast-relay"
echo "Using Interfaces:" $INTERFACES
echo "Using Options --foreground " $OPTS
python3 ./multicast-relay/multicast-relay.py --interfaces $INTERFACES --foreground $OPTS