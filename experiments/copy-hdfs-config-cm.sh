#!/bin/bash

config_map=$(kubectl get cm | grep hdfs-config | awk '{print $1}')

kubectl get cm ${config_map} --namespace=default --export -o yaml |\
   kubectl apply --namespace=polystore-experiments -f -