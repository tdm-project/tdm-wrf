#!/bin/bash

# load config
source ./config.sh

# use resources as working-dir
cd resources || exit 99

# generate and deploy
helm template chart \
     --namespace "${KUBE_NAMESPACE}" \
     --name "${MPI_CLUSTER_NAME}" \
     -f "${VALUES_PATH}/cluster.yaml" \
     -f "${VALUES_PATH}/wrf.yaml" \
     -f ssh-key.yaml | kubectl -n "${KUBE_NAMESPACE}" delete -f -

kubectl delete cm --namespace "${KUBE_NAMESPACE}" "${MPI_CLUSTER_NAME}-config-data"

# delete storage class
kubectl delete sc nfs-${MPI_CLUSTER_NAME}

# delete the namespace
kubectl delete namespace ${KUBE_NAMESPACE}
