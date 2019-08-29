#!/usr/bin/env bash

# set user parameters
RUN_DATA=${1:-"/data/run"}
PROCESSES=${2:-1}
PROCESSES_PER_WORKER=${3:-1}

# exit the run_data path exists or not
if [[ ! -d ${RUN_DATA} ]]; then
  echo "Unable to find RUN_DATA '${RUN_DATA}'";
  exit 99
fi

# move to the working directory
cd "${RUN_DATA}" || exit

# create wrf link
ln -sf /wrf/WRF/run/wrf.exe .

# exec WRF
echo -e "\nStarting WRF @ '${RUN_DATA} with ${PROCESSES} processes ('${PROCESSES_PER_WORKER}' per worker) ...\n"
mpiexec --allow-run-as-root --prefix /usr/lib64/openmpi -mca btl ^openib \
          --hostfile /kube-openmpi/generated/hostfile \
          -v --display-map -np ${PROCESSES} -npernode ${PROCESSES_PER_WORKER} \
          wrf.exe
