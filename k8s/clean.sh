#!/bin/bash

RUN_ID=${1:-run01}

echo -e "Cleaning logs/outputs...."
for i in tdm-stage-openmpi-master tdm-stage-openmpi-worker-0; do  
  echo "Cleaning ${i} ...."
  kubectl exec ${i} sh -- -c "rm -rf /run/wrfout*"
  kubectl exec ${i} sh -- -c "rm -rf /run_results/wrfout*"
done

master_pod="tdm-stage-openmpi-master"
kubectl exec ${master_pod} sh -- -c "rm -rf /run_data/${RUN_ID}/rsl.{err,out}*"
