# multicast-relay docker for Unifi Dream Machine

This is a docker container that implements <https://github.com/alsmith/multicast-relay> to provide mDNS and SSDP on a unfi dream machine.  It will likely work on any multi homed host.  This runs release v1.3 of multicast-relay.

## Required Environment Variables

 To run this container you will need to define the following variables:

| Environment Variable | Default          | Explanation                                                                                                                                    |
|----------------------|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| INTERFACES           | br0 br50         | Space separated list of interfaces. br0 is required for LAN, all other interfaces will be in the format brN where n is the number of the vlan.  This image defaults to vlan50 for the IoT network and assumes your main private network is LAN.  This can be overridden - see below.                                                                                                                                                              |
| OPTS                 |                  | Space separated list of additional command line options, none specified by default, examples below:                                                          |
|                      |     no           | --verbose (if you want verbose logging)                                                                                      |
|                      |     no           | --noMDNS (disables mDNS relaying, e.g. if you are using the unifi one disable this)          |
|                      |     no           | -- noSSDP disables SSDP relaying. (disables SSDP, but not sure why you would want to )                                                                               |
|                      |     no           | --noSonosDiscovery (disables broadcast udp/6969 relaying)                                                                             |
|                      |                     | for full list of options see <https://github.com/alsmith/multicast-relay> |

Any OPT marked above as yes is set by default in the container, to override use the docker run option `-e OPTS="your options"` or -e `OPTS=""`

## Getting Running

** NOTE if you are running this on unifios you will need to use the podman command instead of the docker command **

To get started this is the minimum number of options assuming you have. This assumes you LAN is BR0 (VLAN null / 1) and your IoT network is VLAN #50

`docker run --network=host --restart=always --name ssdp-relay scyto/multicast-relay`

For testing use this to see console output

`docker run --rm -it --network=host  -e OPTS="--verbose" -e INTERFACES="br0 br50"    scyto/multicast-relay`

## More than LAN and 1 VLAN

To run on multiple vlans and have more detailed info and turn off mDNS so you can use the unifi provided one. For example this forwards just SSDP but not mDNS between LAN, VLAN50 and VLAN60:

`docker run --network=host --name ssdp-relay --restart=always -e INTERFACES="br0 br50 br60" -e OPTS="--verbose --noMDNS" scyto/multicast-relay`

If you use LAN as your management VLAN (aka no VLAN / VLAN1) then your command needs to look something like this where  N is each VLAN number

`docker run --network=host --name ssdp-relay --restart=always -e INTERFACES="br10 br75 br90 [etc] " scyto/multicast-relay`

## Firewall Notes
Please note that even when your devices have discovered one another, at least in the Sonos case, a unicast connection will be established from the speakers back to the controlling client running the Sonos app. You will need to make sure that that no firewalling is in place that would prevent connections being established from the SONOS VLAN to the client device VLAN.

E.G. To allow chromecast through the firewall on a vm(photon 4), do not forget to save iptables after everything is working:

`sudo iptables -I INPUT -m pkttype --pkt-type multicast -j ACCEPT`
