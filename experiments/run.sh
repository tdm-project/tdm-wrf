#!/bin/bash

set +x

experiment_name="${1:-polystore-experiment}"

sed -ie  's/id:.*/id: '${experiment_name}'/' values.yaml

MyDir=$(cd `dirname $0` && pwd)
helm repo update
helm install --debug --name "${experiment_name}" -f "${MyDir}/values.yaml" --version 0.1.0 charts/
