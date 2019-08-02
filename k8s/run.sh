#!/usr/bin/env bash

# set the current path
current_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
current_path="."

# TODO: add arg parser to allow parameters: run_ID, ...
run_id="${1:-run01}"
processes=${2:-1}
processes_per_worker=${3:-1}
computational_node_label="transient_computation_node"



# TODO: add procedure to allocate HPC nodes and label them using the proper label

# deploy kube-openmpi
${current_path}/install.sh

# TODO: replace with initialization via init-pod
# dummy procedure for testing: copy prepared test data to the shared folder
# TODO: replace with another test which doesn't show output
if [[ ! $(kubectl exec tdm-stage-openmpi-master -- ls /run_data/${run_id}) ]]; then
  kubectl cp tests/run_dir/* tdm-stage-openmpi-master:/run_data/
fi

# clean
${current_path}/clean.sh ${run_id}

# run simulation
kubectl exec tdm-stage-openmpi-master -- run-wrf ${run_id} ${processes} ${processes_per_worker}

# undeploy kube-openmpi
#${current_path}/delete.sh
