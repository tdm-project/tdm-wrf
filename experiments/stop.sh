#!/bin/bash

set +x
# set the deployment name
experiment_name="${1:-polystore-experiment}"
# delete deployment
helm delete "${experiment_name}" --purge