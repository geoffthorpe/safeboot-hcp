set -e

if [[ -n $HCP_IN_MONOLITH ]]; then
	export HCP_CONFIG_FILE=/usecase/monolith.json
	#export HCP_NOTRACEFILE=1
	#export VERBOSE=3
fi

RARGS="-R 99"

wrapper()
{
	cmd=$1
	if [[ $cmd == start ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			echo "/hcp/caboodle/monolith.py start -l"
		else
			echo "docker-compose up -d"
		fi
	elif [[ $cmd == run ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			echo "/hcp/caboodle/monolith.py run"
		else
			echo "docker-compose run"
		fi
	elif [[ $cmd == exec ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			echo "/hcp/caboodle/monolith.py exec"
		else
			echo "docker-compose exec"
		fi
	elif [[ $cmd == exec-t ]]; then
		if [[ -n $HCP_IN_MONOLITH ]]; then
			echo "/hcp/caboodle/monolith.py exec"
		else
			echo "docker-compose exec -T"
		fi
	else
		echo "Error, unrecognized command: $cmd" >&2
		exit 1
	fi
}

title()
{
	echo "        ##########################"
	echo "        ####  $1"
	echo "        ##########################"
}


