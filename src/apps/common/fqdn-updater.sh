#!/bin/bash

# This task runs backgrounded in each container and implements a "dynamic DNS"
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
# It's implemented in the following way;
#
# - a shared volume, "fqdn", is mounted at $HCP_FQDN_PATH in all containers.
#
# - every $HCP_FQDN_REFRESH seconds, two routines are run;
#
#   1. publish_my_fqdn()
#
#      This writes a "fqdn-$(hostname)" file in the "fqdn" shared volume that
#      publishes all the FQDNs that this container should be visible on. This
#      file gets consumed by all the other containers _as well as our own_ when
#      they (and we) run the update_my_hosts() routine, see item 2 below.
#
#      The FQDNs that we publish are drawn from the following sources;
#
#       - if the file "/hcp-my-fqdn" exists, each line is assumed to be an
#         FQDN. (Does not support white-space, comments, expansions, etc.)
#
#       - if $HCP_FQDN_DEFAULT_DOMAIN is defined, and $HCP_HOSTNAME is defined
#         with one or more (space-separated) values, FQDNs are formed from
#         values in the latter suffixed by the former (dot-separated).
#
#       - if $HCP_FQDN_EXTRA is defined with one or more (space-separated)
#         values, they are assumed to be further, arbitrary FQDNs.
#
#      Additionally, the "fqdn-$(hostname)" file will also contain an entry for
#      $(hostname) itself (which is not a FQDN), mapping it to a deliberately
#      illegal IP address!
#
#       - this illegal mapping will eventually be consumed by all the other
#         containers and integrated into their /etc/hosts files. (See item 2
#         below.) As a result, attempts to address this container by non-FQDN
#         hostname will fail, and it takes precedence over docker-provided DNS
#         (which would otherwise successfully resolve the hostname, which we
#         want to avoid).
#
#       - when our container consumes its own "fqdn-$(hostname)" file, it
#         explicitly filters out that illegal mapping entry. (In fact it would
#         be nice to make it fail locally too, but we'd have a circular
#         problem, as we use the local hostname resolution to find the IP
#         address that all our FQDNs should published to. If we break local
#         resolution of our own hostname, we'd break our published FQDNs too.)
#
#   2. update_my_hosts()
#
#      This reads "fqdn-*" files from the "fqdn" shared volume, thus consuming
#      all the published FQDNs from all the containers, and updates our local
#      /etc/hosts file accordingly. More specifically;
#
#       - we refine our search of the "fqdn" shared volume to only consume
#         files that have been updated within the last $HCP_FQDN_EXPIRY
#         seconds.
#
#       - This ensures that a killed/paused container will eventually disappear
#         from other container's hostname resolution, even though its published
#         FQDNs remain in the shared volume.
#
#       - If a container comes back to life with the same docker hostname as
#         before, it will overwrite the published-FQDNs file from before,
#         otherwise it will publish a new file and the old one will go stale.
#         Either way, other containers will only consume recent/current FQDN
#         publications.
#
#       - As this routine causes the container's own "fqdn-*" file to be
#         consumed also, the illegal mapping of its own hostname is filtered
#         out. (We only want to break hostname resolution for other containers,
#         not ourselves.)

# Parameters
MYBUS=$HCP_FQDN_PATH
MYSLEEP=$HCP_FQDN_REFRESH
MYEXPIRE=$HCP_FQDN_EXPIRY
MYDDOMAIN=$HCP_FQDN_DEFAULT_DOMAIN
BADIPADDRESS=100.100.100.100

# Note, we're using "|| return" liberally wherever a transient "outside our
# control" condition should be tolerated as something that may corrected in due
# course. E.g. if the "fqdn" shared volume isn't mounted or is read-only, or if
# certain environment variables are presently empty/unset, or if /etc/hosts is
# being edited/upgraded or is otherwise not as we expect, etc.

function publish_my_fqdn {
	test -d "$MYBUS" || return
	myhostname=$(hostname) || return
	myipaddress=$(host $myhostname | sed -e "s/^.*has address //") || return
        echo $myipaddress | egrep "^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\$" || return
	echo "#  from $myhostname" > /.hcp-my-fqdn
        myexpanded=$(\
                test -n "$MYDDOMAIN" && \
                for i in $HCP_HOSTNAME; do \
                        echo "$i.$MYDDOMAIN"; \
                done)
	for i in $(test -f /hcp-my-fqdn && cat /hcp-my-fqdn) \
				$myexpanded $HCP_FQDN_EXTRA; \
	do
		echo "$myipaddress $i" >> /.hcp-my-fqdn
	done
        echo "$BADIPADDRESS $myhostname" >> /.hcp-my-fqdn
	cp /.hcp-my-fqdn "$MYBUS/fqdn-$myhostname" || return
}

function update_my_hosts {
	test -d "$MYBUS" || return
	myhostname=$(hostname) || return
	mypeers=$(find "$MYBUS" -maxdepth 1 -name "fqdn-*" -type f \
		-newermt "$MYEXPIRE seconds ago") || return
	cat /etc/hosts | sed -n '/^## HCP FQDNs follow/q;p' > /.hcp-hosts || return
	echo "## HCP FQDNs follow" >> /.hcp-hosts
	echo "" >> /.hcp-hosts
	for i in $mypeers; do
		cat "$i" | grep -v " $myhostname" >> /.hcp-hosts
	done
	cp /.hcp-hosts /etc/hosts || return
}

# Loop until shutdown
while /bin/true; do
	publish_my_fqdn
	update_my_hosts
	# Sleep before rinsing and repeating
	sleep $MYSLEEP
done
