#!/bin/bash

# load config
source ./config.sh

# 
cd resources

# generate ssh keys
./gen-ssh-key.sh

# create the namespace
kubectl create namespace ${KUBE_NAMESPACE}

# create ClusterRoleBinding
kubectl apply -f cluster-role-binding.yaml

# create the volume claim
kubectl apply -f kube-openmpi-run-data-claim.yaml

# generate and deploy
helm template chart \
     --namespace ${KUBE_NAMESPACE} \
     --name ${MPI_CLUSTER_NAME} \
     -f ${VALUES_PATH} \
     -f ssh-key.yaml | kubectl -n ${KUBE_NAMESPACE} apply -f -

# wait until $MPI_CLUSTER_NAME-master is ready
until kubectl get -n ${KUBE_NAMESPACE} po ${MPI_CLUSTER_NAME}-master | grep Running ;
do
    date; sleep 1; echo "";
done