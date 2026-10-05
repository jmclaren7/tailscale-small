#!/usr/bin/env sh
#
# Pulls the container images that aren't present yet, retrying with backoff.
# Anonymous pulls from public registries are rate-limited, and the parallel
# build jobs sometimes get "toomanyrequests: Rate exceeded" back.
#
# Usage: pull-image.sh IMAGE...

set -eu

for image in "$@"; do
	docker image inspect "$image" > /dev/null 2>&1 && continue
	attempt=1
	delay=10
	until docker pull -q "$image"; do
		if [ "$attempt" -ge 5 ]; then
			echo "Could not pull $image after $attempt attempts" >&2
			exit 1
		fi
		echo "Pulling $image failed, retrying in ${delay}s" >&2
		sleep "$delay"
		attempt=$((attempt + 1))
		delay=$((delay * 2))
	done
done
