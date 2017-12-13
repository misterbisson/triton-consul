#!/bin/bash
set -e -o pipefail

help() {
    echo
    echo 'Usage ./setup-multi-datacenter.sh <triton-profile1> [<triton-profile2> [...]]'
    echo
    echo 'Invokes ./setup repeatedly to create one _env file per datacenter per triton profile,'
    echo 'attempting to preserve the triton profile set before this script was invoked.'
    echo
    echo 'Warning: The current triton profile will be changed for each invocation of ./setup.sh,'
    echo 'this may cause unexpected behavior if other commands that read the current triton profile'
    echo 'are executed concurrently!'
}

if [ "$#" -lt 1 ]; then
  help
  exit 1
fi

declare -a written
declare -a consul_hostnames

# check that we won't overwrite any _env files first
if [ -f "_env" ]; then
    echo "Existing env file found, exiting: _env"
fi

# check the names of _env files we expect to generate
for profile in "$@"
do
    if [ -f "_env-$profile" ]; then
        echo "Existing env file found, exiting: _env-$profile"
        exit 2
    fi

    if [ -f "examples/triton/_env-$profile" ]; then
        echo "Existing env file found, exiting: examples/triton/_env-$profile"
        exit 3
    fi

    if [ -f "examples/triton/docker-compose-$profile.yml" ]; then
        echo "Existing docker-compose file found, exiting: examples/triton/docker-compose-$profile.yml"
        exit 4
    fi
done

# check that the docker-compose.yml template is in the right place
if [ ! -f "examples/triton/docker-compose-multi-datacenter.yml.template" ]; then
    echo "Multi-datacenter docker-compose.yml template is missing!"
    exit 5
fi

INITIAL_PROFILE=$(triton profile get | awk '/name:/{print $2}')

# invoke ./setup.sh once per profile
for profile in "$@"
do
    echo "Temporarily switching profile: $profile"
    triton profile set $profile
    eval "$(triton env -d)"
    ./setup.sh

    unset CONSUL
    source examples/triton/_env 

    consul_hostnames+=("\"${CONSUL//cns.joyent.com/triton.zone}\"")

    mv examples/triton/_env "examples/triton/_env-$profile"

    cp examples/triton/docker-compose-multi-datacenter.yml.template \
       "examples/triton/docker-compose-$profile.yml"

    sed -i '' "s/ENV_FILE_NAME/_env-$profile/" "examples/triton/docker-compose-$profile.yml"

    written+=("_env-$profile")
done


# finalize _env and prepare docker-compose.yml files
for profile in "$@"
do
    # add the CONSUL_RETRY_JOIN_WAN addresses to each _env
    echo '# Consul multi-DC bootstrap via Triton CNS' >> examples/triton/_env-$profile
    echo "CONSUL_RETRY_JOIN_WAN=$(IFS=,; echo "${consul_hostnames[*]}")" >> examples/triton/_env-$profile

    cp examples/triton/docker-compose-multi-datacenter.yml.template \
       "examples/triton/docker-compose-$profile.yml"

    sed -i '' "s/ENV_FILE_NAME/_env-$profile/" "examples/triton/docker-compose-$profile.yml"

    written+=("_env-$profile")
done

echo "Wrote: $written"

echo "Clearing triton env"

eval "$(triton env -u)"
triton profile set "$INITIAL_PROFILE"

echo "Restored profile: $INITIAL_PROFILE"
echo "You might want to run eval \"\$(triton env) again"