#!/bin/bash

configmap_name_pattern=${1:-"hdfs-config"}
source_namespace=${2:-"hdfs"}
target_namespace=${3:-"openmpi"}

if [[ -z ${configmap_name_pattern} ]]; then
   echo "ConfigMap name cannot be empty!"
   exit 99
fi

config_map=$(kubectl get cm -n ${source_namespace} | grep ${configmap_name_pattern} | awk '{print $1}')

if [[ -z ${config_map} ]]; then
   echo "Unable to find the ConfigMap ${configmap_name_pattern-config} on namespace ${source_namespace}"
   exit 99
fi

kubectl get cm ${config_map} --namespace=${source_namespace} --export -o yaml |\
   kubectl apply --namespace=${target_namespace} -f -
