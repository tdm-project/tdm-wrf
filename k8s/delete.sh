#!/bin/bash

# set config
CONFIG_DIR=${1:-"../single-domain"}

# load config
RUN_ID=$(basename ${CONFIG_DIR})
MPI_CLUSTER_NAME=tdm-stage-openmpi-${RUN_ID}
KUBE_NAMESPACE=openmpi
VALUES_PATH="${CONFIG_DIR}"


# use resources as working-dir
cd resources || exit 99

# generate and deploy
helm template chart \
     --namespace "${KUBE_NAMESPACE}" \
     --name "${MPI_CLUSTER_NAME}" \
     -f "${VALUES_PATH}/cluster.yaml" \
     -f "${VALUES_PATH}/wrf.yaml" \
     -f ssh-key.yaml | kubectl -n "${KUBE_NAMESPACE}" delete -f -

# wait until $MPI_CLUSTER_NAME-master is ready
until [[ ! $(kubectl get pods -n "${KUBE_NAMESPACE}" | grep "${MPI_CLUSTER_NAME}-master") ]]; do
  date
  sleep 10
  echo "Waiting for master to finish..."
done

#kubectl delete cm --namespace "${KUBE_NAMESPACE}" "${MPI_CLUSTER_NAME}-config-data"

# # delete the namespace
kubectl delete namespace ${KUBE_NAMESPACE}

# # delete storage class
kubectl delete sc nfs-${MPI_CLUSTER_NAME}
