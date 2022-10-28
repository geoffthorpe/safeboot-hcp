#!/bin/bash

source /hcp/common/hcp.sh
log "HCP init: sourced /hcp/common/hcp.sh"

##########
# PURGER #
##########

# The containers produce relevant operational logging to stderr (stdout is
# generally IO between processes so we don't rely on it ever making it all the
# way to a logger). However it's often useful to provide far more detailed
# debugging output, and sometimes on a per-executable basis, so we'd like to
# direct that to files that can be selectively inspected and that don't
# interlace with the monitoring-centric logs. _Yet we must avoid the cardinal
# sin of monotonic-increasing filesystem usage_!
#
# Solution: run a background process that will periodically inspect a
# registered set of directories for debugging files that are older than some
# specified lapse of time and delete them.
if [[ -n $HCP_PURGER_JSON ]]; then
	nohup python3 /hcp/common/purger.py > /.purger.output 2>&1 &
elif [[ -n $HCP_PURGER_JSON_PATH ]]; then
	nohup python3 /hcp/common/purger.py "$(cat $HCP_PURGER_JSON_PATH)" \
		> /.purger.output 2>&1 &
fi

############
# ATTESTER #
############

# Credentials should and do expire, and the enrollsvc's "reenroller"
# functionality helps cater to this, by ensuring that enrollments get refreshed
# on a timely basis. However this requires hosts to repeat the attestation
# process periodically, because this obtains updated creds and installs them
# (and, optionally, triggers hooks to run when particular assets change - eg.
# if /etc/krb5.keytab changes, we want to SIGHUP the sshd process).
if [[ -n $HCP_ATTESTER_PERIOD ]]; then
	nohup python3 /hcp/common/attester.py &
fi

# The following is only relevant when running a closed system inside a docker
# network, usually to test use-cases/scenarios. If you're deploying a production
# service and want your containers interacting with the host and other networks,
# you don't want this.

[[ -z $HCP_NO_INIT ]] || exit 0

################
# FQDN UPDATER #
################

# Force all inter-container comms to use our explicitly orchestrated FQDNs.
# Turns out there's a lot of "history" (and some bad feeling) around docker
# making all sorts of user-friendly DNS assumptions that you can't disable.
#
# My networking goals are multiple;
#
# A. isolation
#   - we want our containers to sit on an network that's isolated from the host
#     and any outside networks.
#   - we want it to be possible to run use-cases that reproduce network names
#     and configs from the real world (eg. "production"), without interacting
#     (and conflicting) with that actual, real world.
#   - this should cover not just outgoing IP connectivity, but it should
#     prevent any use of external hostname resolution too.
# B. explicit FQDNs and nothing else
#   - we want to explicitly say what hostnames and domains our hosts will use
#     to reach each other.
#   - if we're emulating real world scenarios, we don't want any "docker
#     value-added" naming, aliases, or discovery to work. (Otherwise our test
#     environment will allow things that would fail in the real world scenario
#     we're trying to emulate!)
# C. deliberately asynchronous/laggy updates to host resolution
#   - in the real world, hosts can show up on networks, disappear from them,
#     and change network addresses without corresponding updates to DNS being
#     perfectly synchronized. We want to suppress any and all reliance on
#     docker-specific name resolution that is artificially "always current".
#   - Eg. imagine a service initialization flow that implicitly assumes that
#     any peer it can reach can also reach it. In the real world, starting the
#     service and updating DNS may be asynchronous and this flow might be
#     broken by design, but running the scenario in a pure docker-compose
#     environment might never fail.
#
# So ... here's what we do.
#
#  - our network in docker-compose.yml is declared with an "internal: true"
#    attribute, to block access to the host and beyond.
#
#  - we launch /hcp/common/fqdn-updater.sh as a background task to take care
#    of the other requirements. Details of how it works are outlined in
#    fqdn-updater.sh itself.

[[ -d $HCP_FQDN_PATH ]] || exit 0
# If running a CABOODLE_ALONE-style environment, you explicitly do NOT want to
# interact with other hosts on the volume mounted at HCP_FQDN_PATH! Rather than
# teaching docker-compose how to override inherited values (known problem,
# won't be fixed, meh), we simply divert our routines to look somewhere else.
if [[ -n $HCP_CABOODLE_ALONE ]]; then
	export HCP_FQDN_PATH=/caboodle-fqdn-bus
	mkdir -p $HCP_FQDN_PATH
fi
test -x /hcp/common/fqdn-updater.sh &&
	nohup /hcp/common/fqdn-updater.sh > /.fqdn-updater.output 2>&1 &
true
