#!/usr/bin/env bash

set -euo pipefail

BASE_VERSION=latest

docker build -t tdmproject/wrf-base:${BASE_VERSION} \
             -f docker/Dockerfile.wrf-base docker

docker build --build-arg BASE_VERSION=${BASE_VERSION} \
             -f docker/Dockerfile.wrf-wps  \
             -t tdmproject/wrf-wps:${BASE_VERSION} docker

# We enable both dmpar and smpar and nesting
docker build --build-arg BASE_VERSION=${BASE_VERSION} \
             -f docker/Dockerfile.wrf-wrf      \
             --build-arg CMODE=35 --build-arg NEST=1 \
             -t tdmproject/wrf-wrf:${BASE_VERSION} docker

docker build -f docker/Dockerfile.wrf-populate      \
             -t tdmproject/wrf-populate docker


