#!/bin/bash

# This script gets set as the ENTRYPOINT for all HCP containers, so it's where
# we load (and export!) environment variables that we rely on. We also allow
# app-specific container images and/or docker-compose rules to stack their own
# entrypoint on top of this one by setting the environment variable
# HCP_ENTRYPOINT. If that is set, it gets interposed between $0 and $1,
# essentially acting like another ENTRYPOINT. However it comes with an escape
# hatch - if the next parameter equals the value of $HCP_ENTRYPOINT_EXCEPT, the
# entrypoint is ignored.
#
# Eg. if;
# - HCP_ENTRYPOINT="/hcp/tools/run_client.sh -v -v"
# - HCP_ENTRYPOINT_EXCEPT=bash
# then;
#   docker-compose run aclient
#     -> '/hcp/common/launcher.sh /hcp/tools/run_client.sh -v -v'
#   docker-compose run aclient -h
#     -> '/hcp/common/launcher.sh /hcp/tools/run_client.sh -v -v -h'
#   docker-compose run aclient bash
#     -> '/hcp/common/launcher.sh bash'
#   (because of HCP_ENTRYPOINT_EXCEPT it does not run;
#        '/hcp/common/launcher.sh /hcp/tools/run_client.sh -v -v bash')
# So to run an arbitrary command <whatever> without the launcher, try;
#   docker-compose run aclient bash -c "<whatever>"

source /hcp/common/hcp.sh
log "HCP launcher: sourced /hcp/common/hcp.sh"

############
# ATTESTER #
############

# Credentials should and do expire, and the enrollsvc's "reenroller"
# functionality helps cater to this, by ensuring that enrollments get refreshed
# on a timely basis. However this requires hosts to repeat the attestation
# process periodically, because this obtains updated creds and installs them
# (and, optionally, triggers hooks to run when particular assets change - eg.
# if /etc/krb5.keytab changes, we want to SIGHUP the sshd process).
#
# NOTE: we do not do this in init.sh for a reason! This backgrounded service
# gets started for each service that wants it. Ie. in a 'caboodle' environment,
# we don't want the 1-per-machine behavior of init.sh, we want 1-per-service
# behavior. As with the ENTRYPOINT tricks lower down, we undefine the setting
# once this is launched, so we don't accidentally start it again from the same
# process tree. (Eg. because a sub-sub-sub-script includes hcp.sh.)
if [[ -n $HCP_ATTESTER_PERIOD ]]; then
	nohup python3 /hcp/common/attester.py &
	unset HCP_ATTESTER_PERIOD
fi

# NB: due to entanglements between bash (IFS, quoting, ...), docker[-compose],
# and so forth, we do some fiddling below with the argument lists passed to
# 'exec'. It might well be improved with some effort, but it will probably
# always retain some WTFiness until it gets rewritten in python, at which point
# argument lists can be _actual_ arrays, where string quoting and delimitation
# freakiness can't interfere. E.g. if we pass "$1 $2 ... $7" to 'exec' but
# there aren't that many arguments, the invoked script will see $#==7 but with
# empty strings as arguments, which screws up cmd-line processing.  Whereas if
# we pass "$@", then depending on IFS and planet alignment we either observe
# all whitespace and arguments combined to a single string argument ('no such
# executable') or arguments get broken apart by despite whatever efforts you
# take to escape/quote arguments that want to contain spaces or quotes or other
# troublesome characters. (The example that led to this was an when container
# was issued with a command of the form; 'bash -c "..."', where the third
# argument is itself a bash script containing spaces, quotes, semi-colons, and
# so on.)

# Handle HCP_ENTRYPOINT[_EXCEPT]. We only want this ENTRYPOINT processing to
# run on container startup, which it can do by unsetting the environment
# variable before any (and all) other tasks get started.  Eg. this launcher
# (which can be controlled by HCP_INSTANCE) gets used to start tools or
# services in their own containers and it takes care of loading the environment
# for the instance being started and launching any per-container background
# tasks. The caboodle scripting naturally reuses the same invocations when
# trying to start and run those same services and tools in a single-container,
# co-tenant form. Wanting the ENTRYPOINT processing disappear in those
# subsequent uses of the launcher is the use-case that motivates this behavior.
if [[ -n $HCP_ENTRYPOINT ]]; then
	log "HCP launcher: HCP_ENTRYPOINT=$HCP_ENTRYPOINT"
	EP="$HCP_ENTRYPOINT"
	log "HCP launcher: unsetting HCP_ENTRYPOINT"
	unset HCP_ENTRYPOINT
	# Another thing we only want to happen on first-use is the starting up
	# of any background services (usually indicated by environment that is
	# loaded from HCP_INSTANCE).
	log "HCP launcher: running init.sh"
	/hcp/common/init.sh
	if [[ -z $HCP_ENTRYPOINT_EXCEPT || $HCP_ENTRYPOINT_EXCEPT != $1 ]]; then
		estr="$EP $@"
		log "HCP launcher: executing '$estr'"
		[[ -n $7 ]] && exec $EP "$1" "$2" "$3" "$4" "$5" "$6" "$7" ||
		[[ -n $6 ]] && exec $EP "$1" "$2" "$3" "$4" "$5" "$6" ||
		[[ -n $5 ]] && exec $EP "$1" "$2" "$3" "$4" "$5" ||
		[[ -n $4 ]] && exec $EP "$1" "$2" "$3" "$4" ||
		[[ -n $3 ]] && exec $EP "$1" "$2" "$3" ||
		[[ -n $2 ]] && exec $EP "$1" "$2" ||
		[[ -n $1 ]] && exec $EP "$1" ||
		exec $EP
	fi
	log "HCP launcher: bypass! HCP_ENTRYPOINT_EXCEPT==$1"
fi

# If the caller specified a command to run, that shows up in $@ (which is "$1
# $2 $3 ...").
estr="$@"
log "HCP launcher: executing '$estr'"
[[ -n $7 ]] && exec "$1" "$2" "$3" "$4" "$5" "$6" "$7" ||
[[ -n $6 ]] && exec "$1" "$2" "$3" "$4" "$5" "$6" ||
[[ -n $5 ]] && exec "$1" "$2" "$3" "$4" "$5" ||
[[ -n $4 ]] && exec "$1" "$2" "$3" "$4" ||
[[ -n $3 ]] && exec "$1" "$2" "$3" ||
[[ -n $2 ]] && exec "$1" "$2" ||
[[ -n $1 ]] && exec "$1" ||
echo "HCP launcher: no command or HCP_ENTRYPOINT provided" >&2
exit 1
