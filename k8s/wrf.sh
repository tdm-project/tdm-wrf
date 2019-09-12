#!/usr/bin/env bash

# Copyright 2018-2019 CRS4 (http://www.crs4.it/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#set -x
#set -o nounset
#set -o errexit
set -o pipefail
set -o errtrace

DEBUG=1

function log() {
  echo -e "${@}" >&2
}

function debug_log() {
  if [[ -n "${DEBUG:-}" ]]; then
    echo -e "DEBUG: ${@}" >&2
  fi
}

function error_log() {
  echo -e "ERROR: ${@}" >&2
}

function error_trap() {
  error_log "Error at line ${BASH_LINENO[1]} running the following command:\n\n\t${BASH_COMMAND}\n\n"
  error_log "Stack trace:"
  for (( i=1; i < ${#BASH_SOURCE[@]}; ++i)); do
    error_log "$(printf "%$((4*$i))s %s:%s\n" " " "${BASH_SOURCE[$i]}" "${BASH_LINENO[$i]}")"
  done
  exit 2
}

function abspath() {
  local path="${*}"

  if [[ -d "${path}" ]]; then
    echo "$( cd "${path}" >/dev/null && pwd )"
  else
    echo "$( cd "$( dirname "${path}" )" >/dev/null && pwd )/$(basename "${path}")"
  fi
}

#trap error_trap ERR

###############################################################################

# set config
CONFIG_DIR=$(pwd)


function init() {

    # use resources as working-dir
    cd resources || usage_error "Unable to find the 'resources' folder!"

    # generate ssh keys
    ./gen-ssh-key.sh

    # create the namespace
    kubectl create namespace "${KUBE_NAMESPACE}"

    # if no storage class has been specified a dedicated NFS provisioner will be installed
    if [[ ${NFS_PROVISIONER} == "true" ]]; then
        # install nfs-server provisioner
        helm install --debug --namespace "${KUBE_NAMESPACE}" \
                --name "${MPI_CLUSTER_NAME}-nfs-provisioner" \
                -f ${CONFIG_DIR}/nfs-values.yaml \
                --set storageClass.name="nfs-${MPI_CLUSTER_NAME}" \
                stable/nfs-server-provisioner
    fi

    # copy hdfs configmap 
    if [[ -n ${HDFS_CONFIGMAP} ]]; then
        ../copy-hdfs-config-cm.sh ${HDFS_CONFIGMAP} ${HDFS_NAMESPACE} ${KUBE_NAMESPACE}
    fi

    # create
    kubectl create configmap "${MPI_CLUSTER_NAME}-config-data" \
            --namespace "${KUBE_NAMESPACE}" \
            --from-file=${CONFIG_DIR}

    # generate and deploy
    helm template chart \
    --namespace "${KUBE_NAMESPACE}" \
    --name "${MPI_CLUSTER_NAME}" \
    -f "cluster.yaml" \
    -f "${CONFIG_DIR}/wrf.yaml" \
    -f ssh-key.yaml \
    --set mpiMaster.oneShot.enabled=false,mpiMaster.oneShot.autoScaleDownWorkers=false \
    --set persistence.storage_class=${KUBE_STORAGE_CLASS} \
    | kubectl -n "${KUBE_NAMESPACE}" apply -f -

    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ $(kubectl get pod "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" | grep Running) ]]; do
        date
        sleep 5
        echo "Waiting for WRF cluster to be ready..."
    done
}


function exec() {    
    if [[ ${PROCESSES} ]]; then
        # exec the simultation
        kubectl exec "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" -- /bin/bash -c \
                'run-wrf ${RUN_DATA} ${PROCESSES} ${PROCESSES_PER_WORKER}'
    else 
        # exec the simultation
        kubectl exec "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" -- /bin/bash -c \
                'run-wrf ${RUN_DATA}' ${PROCESSES} ${PROCESSES_PER_WORKER}
    fi
    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ $(kubectl logs "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" -c data-writer | grep "__SUCCESS__") ]]; do
        date
        sleep 5
        echo "Waiting for WRF writers to finish..."
    done
    echo "DONE"
}


function clean() {

    # use resources as working-dir
    cd resources || usage_error "Unable to find the 'resources' folder!"

    # delete
    helm template chart \
    --namespace "${KUBE_NAMESPACE}" \
    --name "${MPI_CLUSTER_NAME}" \
    -f "cluster.yaml" \
    -f "${CONFIG_DIR}/wrf.yaml" \
    -f ssh-key.yaml \
    --set persistence.createPVC=false \
    --set global.running.skip.prepare_wd=true,global.running.skip.geo_fetch=true,global.running.skip.gfs_fetch=true,global.running.skip.finalize=true \
    --set mpiMaster.oneShot.enabled=false,mpiMaster.oneShot.autoScaleDownWorkers=false \
    --set persistence.storage_class=${KUBE_STORAGE_CLASS} \
    | kubectl -n "${KUBE_NAMESPACE}" delete -f -

    # # # wait until $MPI_CLUSTER_NAME-master is terminated
    until [[ ! $(kubectl get pods -n "${KUBE_NAMESPACE}" | grep -E "${MPI_CLUSTER_NAME}-(master|worker)") ]]; do
        date
        sleep 5
        echo "Waiting for WRF cluster to be ready..."
    done

    # # generate and deploy
    helm template chart \
    --namespace "${KUBE_NAMESPACE}" \
    --name "${MPI_CLUSTER_NAME}" \
    -f "cluster.yaml" \
    -f "${CONFIG_DIR}/wrf.yaml" \
    -f ssh-key.yaml \
    --set persistence.createPVC=false \
    --set global.running.skip.prepare_wd=true,global.running.skip.geo_fetch=true,global.running.skip.gfs_fetch=true,global.running.skip.finalize=true \
    --set mpiMaster.oneShot.enabled=false,mpiMaster.oneShot.autoScaleDownWorkers=false \
    --set persistence.storage_class=${KUBE_STORAGE_CLASS} \
    | kubectl -n "${KUBE_NAMESPACE}" apply -f -

    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ $(kubectl get pod "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" | grep Running) ]]; do
        date
        sleep 5
        echo "Waiting for WRF cluster to be ready..."
    done
}


function run() {

    # use resources as working-dir
    cd resources || usage_error "Unable to find the 'resources' folder!"

    # generate ssh keys
    ./gen-ssh-key.sh

    # create the namespace
    kubectl create namespace "${KUBE_NAMESPACE}"

    # if no storage class has been specified a dedicated NFS provisioner will be installed
    if [[ ${NFS_PROVISIONER} == "true" ]]; then
        # install nfs-server provisioner
        helm install --debug --namespace "${KUBE_NAMESPACE}" \
                --name "${MPI_CLUSTER_NAME}-nfs-provisioner" \
                -f ${CONFIG_DIR}/nfs-values.yaml \
                --set storageClass.name="nfs-${MPI_CLUSTER_NAME}" \
                stable/nfs-server-provisioner
    fi

    # copy hdfs configmap 
    if [[ -n ${HDFS_CONFIGMAP} ]]; then
        ../copy-hdfs-config-cm.sh ${HDFS_CONFIGMAP} ${HDFS_NAMESPACE} ${KUBE_NAMESPACE}
    fi

    # create
    kubectl create configmap "${MPI_CLUSTER_NAME}-config-data" \
            --namespace "${KUBE_NAMESPACE}" \
            --from-file=${CONFIG_DIR}

    # generate and deploy
    helm template chart \
    --namespace "${KUBE_NAMESPACE}" \
    --name "${MPI_CLUSTER_NAME}" \
    -f "cluster.yaml" \
    -f "${CONFIG_DIR}/wrf.yaml" \
    -f ssh-key.yaml \
    --set persistence.storage_class=${KUBE_STORAGE_CLASS} \
    | kubectl -n "${KUBE_NAMESPACE}" apply -f -

    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ $(kubectl get pod "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" | grep Running) ]]; do
        date
        sleep 5
        echo "Waiting for WRF cluster to be ready..."
    done

    # show WRF master logs
    kubectl logs "${MPI_CLUSTER_NAME}-master" -f -c mpi-master

    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ $(kubectl logs "${MPI_CLUSTER_NAME}-master" -n "${KUBE_NAMESPACE}" -c data-writer | grep "__SUCCESS__") ]]; do
        date
        sleep 5
        echo "Waiting for WRF writers to finish..."
    done
    echo "DONE"
}


function destroy() {
    # use resources as working-dir
    cd resources || usage_error "Unable to find the 'resources' folder!"

    # generate and deploy
    helm template chart \
        --namespace "${KUBE_NAMESPACE}" \
        --name "${MPI_CLUSTER_NAME}" \
        -f "cluster.yaml" \
        -f "${CONFIG_DIR}/wrf.yaml" \
        --set persistence.storage_class=${KUBE_STORAGE_CLASS} \
        -f ssh-key.yaml | kubectl -n "${KUBE_NAMESPACE}" delete -f -

    # wait until $MPI_CLUSTER_NAME-master is ready
    until [[ ! $(kubectl get pods -n "${KUBE_NAMESPACE}" | grep "${MPI_CLUSTER_NAME}-master") ]]; do
        date
        sleep 10
        echo "Waiting for WRF master to finish..."
    done

    # delete storage class
    if [[ ${NFS_PROVISIONER} == "true" ]]; then
        #kubectl delete sc nfs-${MPI_CLUSTER_NAME}
        helm delete "${MPI_CLUSTER_NAME}-nfs-provisioner"
    fi

        # delete current configuration
    kubectl delete cm --namespace "${KUBE_NAMESPACE}" "${MPI_CLUSTER_NAME}-config-data"

    # delete the namespace
    kubectl delete namespace ${KUBE_NAMESPACE}
}


function usage_error() {
  if [[ $# > 0 ]]; then
    echo -e "ERROR: ${@}" >&2
  fi
  help
  exit 2
}

function help() {
  local script_name=$(basename "$0")
  echo -e "\nUsage of '${script_name}'

  ${script_name} <COMMAND> [OPTIONS]
  ${script_name} -h        prints this help message
  ${script_name} -v        prints the '${script_name}' version

  COMMAND:
    init                   initializes infrastructure and download datasets required to run a WRF simulation 
    run                    executes initialization and run a WRF simulation
    exec                   executes a WRF simulation on a initialized infrastructure
    clean                  softly reinitializes the existing infrastructure
    destroy                releases all the allocated resources

  OPTIONS:
     -c|--config-dir                Path to the directory containing the WRF simulation's configuration
                                    (i.e., see examples 'single-domain', 'sardinia-low-res') 
     -n|--name                      WRF simulation name (used as prefix for all the k8s resources)
     -p|--processes                 overwrites the number of processes defined on wrf.yaml
    -np|--processes-per-worker      overwrites the number of processes per worker defined on wrf.yaml
    -ns|--namespace                 Kubernetes namespace to be used to deploy WRF infrastructure
    -sc|--storage-class             Kubernetes storage class to be used to store shared data between k8s components
    --hdfs-namespace                Namespace of the HDFS deployment to be used
    --hdfs-configmap                Name of config map containing the HDFS configuration
  " >&2
}

# extract value for a given option
function parse_option(){
  local opt=${1}
  local value=$(echo ${opt} | sed -E 's/(--(-|[[:alnum:]])+)([[:space:]]|=)([[:alnum:]]+)/\4/')
  debug_log "Value for option '${opt}' ==> ${value}"  
  if [[ $opt != *"="* ]]; then
    SKIP_EXTRA_ARG=true
  fi
  echo ${value}
}

# defaults
KUBE_NAMESPACE=wrf-openmpi
NFS_PROVISIONER=false

# Collect arguments to be passed on to the next program in an array, rather than
# a simple string. This choice lets us deal with arguments that contain spaces.
EXTRA_ARGS=()

# reset flag to skip the current option
SKIP_EXTRA_ARG=false

# parse arguments
while [ -n "${1}" ]; do
    # Copy so we can modify it (can't modify $1)
    OPT="${1}"
    # Detect argument termination
    if [ x"${OPT}" = x"--" ]; then
        shift
        for OPT ; do
            # append to array
            EXTRA_ARGS+=("${OPT}")
        done
        break
    fi
    # Parse current opt
    while [ x"${OPT}" != x"-" ] ; do
        
        # parse option
        case "${OPT}" in
          
          init | run | exec | destroy | clean )
              COMMAND="$1" ;;

          -h) help; exit 0 ;;
          -v) print_version; exit 0 ;;

          -c | --config-dir )
            CONFIG_DIR=$(parse_option "${OPT} $2") ;; 

          -n | --name )
            RUN_ID=$(parse_option "${OPT} $2") ;;

          -ns | --namespace )
            KUBE_NAMESPACE=$(parse_option "${OPT} $2") ;;

          -p | --processes )
            PROCESSES=$(parse_option "${OPT} $2") ;;

          -np | --processes-per-worker )
            PROCESSES_PER_WORKER=$(parse_option "${OPT} $2") ;;

          -sc | --storage-class )
            KUBE_STORAGE_CLASS=$(parse_option "${OPT} $2") ;;

          --hdfs-namespace )
            HDFS_NAMESPACE=$(parse_option "${OPT} $2") ;;

          --hdfs-configmap )
            HDFS_CONFIGMAP=$(parse_option "${OPT} $2") ;;

          * )
              debug_log "Default case: ${OPT}"
              # append to array
              EXTRA_ARGS+=("${OPT}") 
              break
              ;;
        esac        
        # Check for multiple short options
        # NOTICE: be sure to update this pattern to match valid options
        NEXTOPT="${OPT#-[cfr]}" # try removing single short opt
        if [ x"${OPT}" != x"$NEXTOPT" ] ; then
          OPT="-$NEXTOPT"  # multiple short opts, keep going
        else          
          break  # long form, exit inner loop
        fi
        break
    done
    # move to the next param
    shift
    # skip the next param if it comes from an option already parsed
    if [[ ${1} && ${SKIP_EXTRA_ARG} == true ]]; then
        # reset flag to skip the current option
        SKIP_EXTRA_ARG=false
        # skip the current extra arg
        shift
    fi
done

# get the absolute path of CONFIG_DIR
CONFIG_DIR=$(abspath ${CONFIG_DIR})

# use config_dir as RUN_ID if RUN_ID has been defined
if [[ -z ${RUN_ID} ]]; then
    RUN_ID=$(basename ${CONFIG_DIR})
fi

# load config
MPI_CLUSTER_NAME="${RUN_ID}"

debug_log "COMMAND: ${COMMAND}"
debug_log "RUN ID: ${RUN_ID}"
debug_log "K8S NAMESPACE: ${KUBE_NAMESPACE}"
debug_log "PROCESSES: ${PROCESSES}"
debug_log "PROCESSES_PER_WORKER: ${PROCESSES_PER_WORKER}"
debug_log "CONFIG DIR: ${CONFIG_DIR}"
debug_log "EXTRA ARGS: ${EXTRA_ARGS}"
debug_log "STORAGE CLASS: ${KUBE_STORAGE_CLASS}"
debug_log "HDFS NAMESPACE: ${HDFS_NAMESPACE}"
debug_log "HDFS CONFIGMAP: ${HDFS_CONFIGMAP}"
if [[ -z "${KUBE_STORAGE_CLASS}" ]]; then
    KUBE_STORAGE_CLASS="nfs-${MPI_CLUSTER_NAME}"
    NFS_PROVISIONER="true"
    debug_log "STORAGE CLASS not defined. Using a new storage-class: '${KUBE_STORAGE_CLASS}'!"
    debug_log "NFS_PROVISIONER: ${NFS_PROVISIONER}"
fi

for i in "${EXTRA_ARGS[@]}"; do
  debug_log "- ARG: ${i}"
done

AVAILABLE_COMMANDS="init run exec clean destroy"
if [[ ${AVAILABLE_COMMANDS} == *"${COMMAND}"* ]]; then
    ${COMMAND}
else
    usage_error "Command not valid!"
fi