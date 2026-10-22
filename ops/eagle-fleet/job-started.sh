#!/bin/sh
set -eu
# This hook runs before service containers and action pre/main steps. Wait until
# the Windows supervisor has persisted this job's deadline before allowing code.
: > /home/runner/.eagle-job-started
attempt=0
while [ ! -e /home/runner/.eagle-job-start-ack ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 180 ]; then
        echo '::error::Eagle supervisor did not acknowledge the job deadline'
        exit 1
    fi
    sleep 1
done
