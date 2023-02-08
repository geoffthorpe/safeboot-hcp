#!/usr/bin/python3
##  vim: set expandtab shiftwidth=4 softtabstop=4:  ##

# This task runs backgrounded for each workload and implements a "dynamic DNS"
# solution of grotesque and yet practical proportions.
#
# Two goals;
#
# A. Supporting real-world configurations.
#
#    We want the hosts to address each other (or fail) using real-world FQDNs
#    and configurations (e.g. potentially the same as production), rather than
#    using docker hostnames, etc. This is especially important when testing
#    services, protocols, architectures that are strongly entangled with FQDNs
#    and their semantics, such as Kerberos and PKIX (and HTTPS) functionality.
#
# B. Helping error/resiliency testing.
#
#    We want hostname resolution in each container to react when other
#    containers pause, unpause, stop, start, hang, crash, change address, etc.
#    When a container disappears (or changes address), we want the hostname
#    resolution in other containers to drop or update that FQDN, after some
#    suitable "reaction time", so there's a bounded but non-zero delay between
#    the container becoming unreachable and its hostname being unresolvable,
#    and similarly a delay between it becoming reachable (and active) and its
#    hostname becoming resolvable. In this way, it should be possible to test
#    inter-service resiliency by randomly pausing and unpausing services, with
#    different effects depending on how long it is inactive.
#
# The JSON configuration takes the following form;
#   {
#       "exec": "/hcp/common/fqdn_updater.py",   <-- this executable
#       "until": "/etc/example-alive",   <-- set once the service is running
#       "path": "/fqdn-bus",   <-- the path mounted into all containers
#       "refresh": 5,   <-- number of seconds between refreshes
#       "retry": 15,   <-- number of seconds after failure before a retry
#       "expiry": 20,   <-- number of seconds before another container's refresh
#                           is considered "stale", ie. it disappears.
#       "hostnames": [ "this-container", "service.alias" ],
#       "default_domain": "hcphacking.xyz",
#       "extra_fqdns": [ "host-foo.company.com", "host-bar.intranet" ],
#       "bad_address": "100.100.100.100"
#   }
# 
# It's implemented in the following way;
#
# - A shared volume, "fqdn-bus", is mounted at the 'path' setting. All
#   participating containers mount this same state and run their own instance
#   of this updater service. (They mount the volume at different paths, their
#   configs will represent that accordingly).
#
# - Every 'refresh' seconds, this service will run two routines (described
#   below) to (a) publish its FQDN records on the bus, and (b) recolt the FQDN
#   records published by the other containers. In this way, this service
#   manipulates the local /etc/hosts file to provide name-resolution.
#
# - If an update fails for any reason, we pause for 'retry' seconds (rather
#   than 'refresh') before retrying.
#
# - The 'expiry' setting is used as a kind of "watchdog", such that if any
#   container's FQDN records on the bus have not been updated since this many
#   seconds, its records are considered stale (or rather, the container is
#   considered "gone"), meaning that those hosts will cease to show up in the
#   /etc/hosts files of the other containers.
#
# - The FQDNs of the local container consist of;
#
#     - All entries in the 'hostnames' array, suffixed by the 'default_domain'.
#       In the example above, this would contribute;
#           this-container.hcphacking.xyz, service.alias.hcphacking.xyz
#
#     - All entries in 'extra_fqdns', verbatim. In the example, this is;
#           host-foo.company.com, host-bar.intranet
#
#     - If the file "/hcp-my-fqdn" exists, it is assumed to be a \n-delimited,
#       one-FQDN-per-line list of additional FQDNs. (This does not tolerate
#       extra whitespace, comments, expansions, or anything else of the sort.)
#
# - All these FQDNs are mapped to the canonically-determined IPv4 address of
#   the container.
#
# - Finally, to ensure that a scenario does not accidentally depend (and
#   succeed based) on the docker networking/hostnames, we also take the
#   docker-assigned hostname (as returned by the hostname(1) utility) and
#   deliberately publish it with a mapping to a known-bad IP address! This is
#   to help ensure that running the same scenario "in the real world" will not
#   fail because some software behavior or mis-configuration had crept in that
#   tied the scenario to the specifics of the development workflow. The bad
#   address to use is given by the 'bad_address' configuration field, or
#   defaults to 100.100.100.100 if this is not provided.
#
# Regarding the two routines (publish and recolt) mentioned above, here are the
# specifics.
#
#   1. publish()
#
#      This writes a "fqdn-$(hostname).json" file in the "fqdn-bus" shared
#      volume that publishes all the FQDNs that this container should be
#      visible on, as described above. This JSON file is of the form;
#           {
#               'FQDNs': [
#                   'first.hostname.hcphacking.xyz',
#                   'hrb0137.raw.hcphacking.xyz',
#                   'alias.someother.net'
#               ],
#               'bad': 'bd8ff488bf71',
#               'networks': [
#                   { 'addr': '192.168.0.3', 'netmask': '255.255.255.0' },
#                   { 'addr': '172.18.0.37', 'netmask': '255.255.0.0' }
#               ]
#           }
#
#      The 'bad' entry is the current (docker-assigned) hostname, which other
#      hosts will intentionally map to a bad IP address.
#
#      The 'networks' information is provided by the 'netifaces' python module
#      and the entries may contain other fields than 'addr' and 'netmask', but
#      we ignore them. (Eg. 'broadcast', 'peer', etc.)
#
#   2. recolt()
#
#      This reads "fqdn-*.json" files from the "fqdn-bus" shared volume,
#      _including our own_, and updates our local /etc/hosts file accordingly.
#
#      As described earlier, we refine our search of the "fqdn-bus" volume to
#      only consume files that have been updated within the last 'expiry'
#      seconds.
#
#      A container's JSON representation may have multiple IP addresses, so we
#      try to find one that is in one of our own networks, and we create map
#      that container's FQDNs to that IP address. (Other containers may map
#      that container's FQDNs to a different choice of IP address, of course.)
#
# Because each copy of this fqdn_updater.sh will act as though it owns
# /etc/hosts and can rewrite it at will, you might be wondering how we handle
# co-tenant workloads ... indeed!
#
# The trick is that all but one of the workloads should have the
# ".fqdn_updater.publish_only" attribute set in their JSON config. (It doesn't
# matter what the value is, only that the attribute be there - feel free to set
# it to null.) In the 'monolith' case, the container itself (which runs
# launcher.py as the entrypoint) is started up with an instance of fqdn_updater
# that owns and will continue to own /etc/hosts - in other words, it's the only
# one that will run the recolt() function. All subsequent workloads started in
# the container will dynamically insert that "publish_only" attribute, meaning
# they bypass recolt() and only do the publish() step.

import os
import sys
import json
import socket
import time
import pathlib
import datetime
import glob
import shutil
import netifaces as net
import ipaddress as ip

sys.path.insert(1, '/hcp/common')
from hcp_common import touch, log, bail, hcp_config_extract

log("Running FQDN publishing and discovery mechanism")

myid = hcp_config_extract('id', or_default = True, default = 'unknown_id')
etc = f"/etc/hcp/{myid}"
myuntil = f"{etc}/touch-fqdn-alive"

mydomain = hcp_config_extract('.default_domain', must_exist = True)
_myhostname = hcp_config_extract('.id', must_exist = True)
myhostname = f"{_myhostname}.{mydomain}"
myhostnames = hcp_config_extract('.hostnames', or_default = True, default = [])
#myhostnames = [ f"{h}.{mydomain}" for h in _myhostnames ]

# We pull our config structure as a whole, once, then dig into it locally. I.e.
# we don't pull each attribute via hcp_config_extract()
myconfig = hcp_config_extract('.fqdn_updater', must_exist = True)
log(f"myconfig={myconfig}")
test_myuntil = None
if 'until' in myconfig:
    test_myuntil = myconfig['until']
    if test_myuntil != myuntil:
        bail(f"Misconfiguration: {myuntil} != {test_myuntil}")
mydir = myconfig['path']
myrefresh = myconfig['refresh']
myretry = myrefresh
if 'retry' in myconfig:
    myretry = myconfig['retry']
myexpiry = myconfig['expiry']
myextra = None
if 'extra_fqdns' in myconfig:
    myextra = myconfig['extra_fqdns']
mybad = '100.100.100.100'
if 'bad_address' in myconfig:
    mybad = myconfig['bad_address']
mypublishonly = False
if 'publish_only' in myconfig:
    mypublishonly = True

summary = '''
    until={_until}
    dir={_dir}
    refresh={_refresh}
    retry={_retry}
    expiry={_expiry}
    hostnames={_hostnames}
    domain={_domain}
    extra={_extra}
    bad={_bad}
    hostname={_hostname}
'''.format(_until = myuntil, _dir = mydir, _refresh = myrefresh,
    _retry = myretry, _expiry = myexpiry, _hostnames = myhostnames,
    _domain = mydomain, _extra = myextra, _bad = mybad,
    _hostname = myhostname)

log(f"Summary;\n{summary}")

def debug(s):
    if 'VERBOSE' in os.environ:
        if len(os.environ['VERBOSE']) > 0:
            log(s)

# Return a list of dicts detailing each of our (non-localhost) IPv4 addresses
# and corresponding netmask.
def our_networks():
    result = []
    ifaces = net.interfaces()
    for i in ifaces:
        if i == 'lo':
            continue
        addrs = net.ifaddresses(i)
        if net.AF_INET not in addrs:
            continue
        ip4s = addrs[net.AF_INET]
        result += ip4s
    return result

# Given another host's JSON and the list returned from our_networks(), find one of
# the host's IP addresses that we can reach.
def choose_address(pjson, networks):
    found = None
    first = None
    debug("starting choose_address")
    debug(f"pjson={pjson}")
    debug(f"networks={networks}")
    for pn in pjson['networks']:
        p = f"{pn['addr']}"
        pp = ip.ip_address(p)
        debug(f"pp={pp}")
        for n in networks:
            nn = ip.ip_interface(f"{n['addr']}/{n['netmask']}")
            debug(f"nn={nn}")
            nnn = nn.network
            debug(f"nnn={nnn}")
            if pp in nnn:
                debug("Match!")
                found = p
                break
            else:
                debug("No match")
            if not first:
                first = p
        if found:
            break
    if not found:
        debug("No match, using first address instead")
        found = first
    return found

# Given a line from /etc/hosts and the list returned from our_networks(),
# figure out if this is a docker-provided mapping for the docker-hostname to a
# non-localhost IP address. (If so, we won't include it when we rewrite
# /etc/hosts.)
def hosts_filter(hostline, networks):
    fields = hostline.split()
    for n in networks:
        if n['addr'] == fields[0]:
            return True
    return False

def publish():
    forjson = {}
    forjson['FQDNs'] = []
    for h in myhostnames:
        forjson['FQDNs'] += [ f"{h}.{mydomain}" ]
    if myextra:
        for h in myextra:
            forjson['FQDNs'] += [ f"{h}" ]
    if os.path.isfile('/hcp-my-fqdn'):
        with open('/hcp-my-fqdn', 'r') as fp:
            for line in fp:
                forjson['FQDNs'] += [ line.strip() ]
    forjson['bad'] = f"{myhostname}"
    forjson['networks'] = our_networks()
    src = f"{mydir}/.new.fqdn-{myhostname}.json"
    dst = f"{mydir}/fqdn-{myhostname}.json"
    with open(src, 'w') as fp:
        json.dump(forjson, fp)
    os.replace(src, dst)

def recolt():
    debug("start recolt")
    peers = glob.glob(f"{mydir}/fqdn-*.json")
    debug(f"peers={peers}")
    if len(peers) == 0:
        log(f"strange: recolt() bailing out, found no JSONs")
        return
    networks = our_networks()
    basehosts = open('/etc/hosts', 'r').readlines()
    lines = []
    for l in basehosts:
        ll=l.strip()
        if ll.startswith('## HCP FQDNs follow'):
            break
        if not hosts_filter(l, networks):
            lines += [ l.strip() ]
    lines += [ '## HCP FQDNs follow' ]
    now = datetime.datetime.now(datetime.timezone.utc)
    td = datetime.timedelta(seconds = myexpiry)
    cutoff = now - td
    for p in peers:
        debug(f"peer={p}")
        st = os.stat(p)
        mdatetime = datetime.datetime.fromtimestamp(st.st_mtime,
                        datetime.timezone.utc)
        if mdatetime < cutoff:
            debug(f"too old")
            # Too old, ignore
            continue
        with open(p, 'r') as fp:
            pjson = json.load(fp)
        pipaddr = choose_address(pjson, networks)
        lines += [ f"# Entries from {p}" ]
        for l in pjson['FQDNs']:
            lines += [ f"{pipaddr} {l}" ]
        lines += [ f"{pjson['bad']} {mybad}" ]
    with open('/etc/.new.hosts', 'w') as fp:
        for l in lines:
            fp.write(f"{l}\n")
    # We'd rather use os.replace(), but docker sometimes does weird things, and
    # this can cause a 'Device or resource busy' failure.
    shutil.copyfile('/etc/.new.hosts', '/etc/hosts')

def loop():
    while True:
        try:
            if not os.path.isdir(mydir):
                log(f"Warning, fqdn_updater path doesn't exist: {mydir}")
                raise Exception()
            publish()
            if not mypublishonly:
                recolt()
            if myuntil:
                touch (myuntil)
            log(f"Updated, sleeping for {myrefresh} seconds")
            time.sleep(myrefresh)
        except Exception as e:
            log(f"Error occurred, sleeping for {myretry} seconds")
            log(f"{e}")
            time.sleep(myretry)

if __name__ == '__main__':
    loop()
