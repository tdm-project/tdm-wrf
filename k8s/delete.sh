#!/bin/bash

# load config
source ./config.sh

# 
cd resources

# generate and deploy
helm template chart \
     --namespace ${KUBE_NAMESPACE} \
     --name ${MPI_CLUSTER_NAME} \
     -f ${VALUES_PATH} \
     -f ssh-key.yaml | kubectl -n ${KUBE_NAMESPACE} delete -f -

# delete the namespace
kubectl delete namespace ${KUBE_NAMESPACE}