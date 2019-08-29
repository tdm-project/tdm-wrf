#!/bin/bash

# load config
source ./config.sh

# change wd
cd resources || exit 99

# generate ssh keys
./gen-ssh-key.sh

# create the namespace
kubectl create namespace "${KUBE_NAMESPACE}"

# install nfs-server provisioner
helm install --debug --namespace "${KUBE_NAMESPACE}" \
           -f ${VALUES_PATH}/nfs-values.yaml \
           --set storageClass.name="nfs-${MPI_CLUSTER_NAME}" \
           stable/nfs-server-provisioner

# create the volumes
kubectl apply -f pvc-data.yaml

# create ClusterRoleBinding
kubectl apply -f cluster-role-binding.yaml

# copy hdfs configmap
../copy-hdfs-config-cm.sh

# create
kubectl create configmap "${MPI_CLUSTER_NAME}-config-data" \
        --namespace "${KUBE_NAMESPACE}" \
        --from-file=${VALUES_PATH}

# generate and deploy
helm template chart \
  --namespace "${KUBE_NAMESPACE}" \
  --name "${MPI_CLUSTER_NAME}" \
  -f "${VALUES_PATH}/cluster.yaml" \
  -f "${VALUES_PATH}/wrf.yaml" \
  -f ssh-key.yaml | kubectl -n "${KUBE_NAMESPACE}" apply -f -

# wait until $MPI_CLUSTER_NAME-master is ready
until kubectl get -n "${KUBE_NAMESPACE}" po "${MPI_CLUSTER_NAME}-master" | grep Running; do
  date
  sleep 1
  echo "Waiting for kube-openmpi..."
done

# show WRF master logs
kubectl logs ${KUBE_NAMESPACE}-master -f -c mpi-master
