#!/bin/bash

source_namespace=${1:-"hdfs"}
target_namespace=${2:-"openmpi"}

config_map=$(kubectl get cm -n ${source_namespace} | grep hdfs-config | awk '{print $1}')

kubectl get cm ${config_map} --namespace=${source_namespace} --export -o yaml |\
   kubectl apply --namespace=${target_namespace} -f -
