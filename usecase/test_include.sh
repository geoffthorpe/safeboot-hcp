# For interactive shells, don't "set -e", it can be (more than) mildly
# inconvenient to have the shell exit any time you run a command that returns a
# non-zero status code. It's good discipline for scripts though.
[[ -z $PS1 ]] && set -e

if [[ -n $HCP_IN_MONOLITH ]]; then
	export HCP_CONFIG_FILE=/usecase/monolith.json
	#export HCP_NOTRACEFILE=1
	#export VERBOSE=3
fi

RARGS="-R 99"

title()
{
	echo "        ##########################"
	echo "        ####  $1"
	echo "        ##########################"
}

wrapper()
{
	cmd=$1
	shift
	targets=""
	if [[ $# -lt 1 ]]; then
		echo "Error, 'wrapper' called with insufficient parameters" >&2
		exit 1
	fi
	while [[ $# -gt 0 ]]; do
		item=$1
		shift
		if [[ $item == "--" ]]; then
			break
		fi
		targets="$targets $item"
	done
	targets=$(echo "$targets" | sed -e 's/^[[:space:]]*//')
	if [[ $cmd == start ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py start -l"
		else
			cmdline="docker-compose up -d"
		fi
	elif [[ $cmd == run_fg ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py run_fg"
		else
			cmdline="docker-compose run --rm"
		fi
	elif [[ $cmd == run_bg ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py run_bg"
		else
			cmdline="docker-compose up -d"
		fi
	elif [[ $cmd == exec ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py exec"
		else
			cmdline="docker-compose exec"
		fi
	elif [[ $cmd == exec_t ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py exec"
		else
			cmdline="docker-compose exec -T"
		fi
	elif [[ $cmd == shell ]]; then
		# The first parameter should be the workload to execute the shell in,
		# and anything else is weird (if we pass them as args to bash, you won't
		# get a shell...). So force the arguments that get passed.
		set -- $1 bash
		if [[ -n $HCP_IN_MONOLITH ]]; then
			cmdline="/hcp/caboodle/monolith.py exec"
		else
			cmdline="docker-compose exec"
		fi
	else
		echo "Error, unrecognized command: $cmd" >&2
		exit 1
	fi
	if [[ -n $VERBOSE && $VERBOSE -gt 0 ]]; then
		echo "wrapper() about to run;" >&2
		echo "- $cmdline $@" >&2
		echo "- HCP_LAUNCHER_TGTS='$targets'" >&2
	fi
	if [[ $cmd == shell ]]; then
		echo "Starting '$1' shell" >&2
	fi
	HCP_LAUNCHER_TGTS="$targets" $cmdline "$@"
	if [[ $cmd == shell ]]; then
		echo "Exited '$1' shell" >&2
	fi
}

# 'do_core_*' routines are for HCP containers (whether foregrounded apps or
# backgrounded services) that do not have TPMs and do not run a local
# "attester" agent. This includes;
# - all instances of the core HCP core services ('enrollsvc', 'attestsvc'):
#       emgmt, erepl, arepl, ahcp
# - all instances of the 'swtpmsvc' software TPM sidecar:
#       aclient_tpm, kdc_primary_tpm, kdc_secondary_tpm,
#       sherver_tpm, workstation1_tpm
# - all instances of the 'policysvc' policy service sidecar:
#       emgmt_pol, kdc_primary_pol, kdc_secondary_pol
# - all instances of the 'orchestrator' tool:
#       orchestrator
# - all instances of the low-level attestation test client:
#       aclient

# do_core_start_lazy()
# - starts one or more HCP core services using the default target list, which
#   is;
#       start-fqdn setup-global setup-local start-services
#   this will perform global initialization if it hasn't already been done.
do_core_start_lazy() {
	wrapper start -- "$@"
}

# do_core_start()
# - starts one or more HCP core services without support for
#   lazy-initialization (it will fail if initialization hasn't yet occurred).
#   The target list is;
#       start-fqdn setup-local start-services
do_core_start()
{
	wrapper start start-fqdn setup-local start-services -- "$@"
}

# do_core_setup()
# - performs global initialization as a foregrounded task. The target list is;
#       start-fqdn setup-global
do_core_setup()
{
	wrapper run_fg start-fqdn setup-global -- "$@"
}

# do_core_fg()
# - runs a foregrounded task/tool. The first argument is the workload name. If
#   there are arguments, they indicate "what to run", so we set the target list
#   to "start-fqdn" only. Otherwise, thedefault target list is used because
#   that determines the default choice of "what to run".
do_core_fg()
{
	if [[ $# -eq 0 ]]; then
		echo "Error, do_core_fg() requires at least one argument" >&2
		exit 1
	elif [[ $# -eq 1 ]]; then
		wrapper run_fg -- "$@"
	else
		wrapper run_fg start-fqdn -- "$@"
	fi
}

#
# 'do_normal_*' routines are HCP-bootstrapped containers, so they have TPMs and
# each start an "attester" agent running early during start up (they also block
# for this agent to successfully complete at least one attestation - to
# simplify service synchronization and not need other components to handle the
# error-retry cases that otherwise occur). This includes;
# - all instances of the KDC service ('kdcsvc'):
#       kdc_primary, kdc_secondary
# - all instances of the SSH service ('sshsvc'):
#       sherver
# - all instances of the stateful client tool ('do_nothing'):
#       workstation1

# do_normal_* variants of the above functions all add the 'start-attester'
# to the target list.
do_normal_start_lazy() {
	wrapper start -- "$@"
}
do_normal_start()
{
	wrapper start start-fqdn start-attester setup-local start-services -- "$@"
}
do_normal_setup()
{
	wrapper run_fg start-fqdn start-attester setup-global -- "$@"
}
do_normal_fg()
{
	if [[ $# -eq 0 ]]; then
		echo "Error, do_normal_fg() requires at least one argument" >&2
		exit 1
	elif [[ $# -eq 1 ]]; then
		wrapper run_fg -- "$@"
	else
		wrapper run_fg start-fqdn start-attester -- "$@"
	fi
}

#
# 'do_exec' and 'do_exec_t' work the same way with core and normal containers.
# The latter ensures that no TTY is allocated (in the "docker-compose exec"
# case, this will add the "-T" flag).
do_exec()
{
	wrapper exec -- "$@"
}
do_exec_t()
{
	wrapper exec_t -- "$@"
}

#
# 'do_shell' is core/normal-agnostic, like do_exec.
do_shell()
{
	wrapper shell -- "$@"
}
