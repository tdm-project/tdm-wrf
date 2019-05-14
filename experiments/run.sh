#!/bin/bash

set +x

# set experiment name
experiment_name="${1:-polystore-experiment-$(date '+%Y%m%d-%H%M%S')}"
# update values with the experiment name
sed -ie  's/id:.*/id: "'${experiment_name}'"/' values.yaml
# set namespace
namespace="polystore-experiments" # notice that, due to the hdfs config-map
                    # 'default' namespace, only default namespace is valid
MyDir=$(cd `dirname $0` && pwd)
helm repo update
helm install --debug \
    --name "${experiment_name}" \
    -f "${MyDir}/values.yaml" \
    --namespace "${namespace}" \
    --version 0.1.0 \
    charts/

