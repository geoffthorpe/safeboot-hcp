#!/bin/bash

# The following is only relevant when running a closed system inside a docker
# network, usually to test use-cases/scenarios. If you're deploying a production
# service and want your containers interacting with the host and other networks,
# you don't want this.

[[ -n $HCP_FQDN_PATH ]] || exit 0

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

test -x /hcp/common/fqdn-updater.sh &&
	nohup /hcp/common/fqdn-updater.sh > /.hcp-fqdn-updater.output 2>&1 &
