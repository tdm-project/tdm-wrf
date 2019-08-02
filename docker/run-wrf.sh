#!/usr/bin/env bash

run_id=${1}
processes=${2:-1}
processes_per_worker=${3:-1}
# TODO: add options for np and npernode

# TODO: fixme using env var
run_path="/run_data/${run_id}"

if [[ ! -d ${run_path} ]]; then
  echo "Unable to find rundir '${run_path}'";
  exit -1
fi

cd ${run_path}

mpiexec --allow-run-as-root --prefix /usr/lib64/openmpi -mca btl ^openib \
          --hostfile /kube-openmpi/generated/hostfile \
          -v --display-map -np ${processes} -npernode ${processes_per_worker} \
          wrf.exe
