#!/usr/bin/env bash

set -euo pipefail

BASE_VERSION=latest

docker build -t tdm/wrf-base:${BASE_VERSION} \
       -f docker/Dockerfile.wrf-base docker

docker build --build-arg BASE_VERSION=${BASE_VERSION} \
             -f docker/Dockerfile.wrf-wps  \
             -t tdm/wrf-wps:${BASE_VERSION} docker

# We enable both dmpar and smpar and nesting
docker build --build-arg BASE_VERSION=${BASE_VERSION} \
             -f docker/Dockerfile.wrf-wrf      \
             --build-arg CMODE=35 --build-arg NEST=1 \
             -t tdm/wrf-wrf:${BASE_VERSION} docker

docker build -f docker/Dockerfile.wrf-populate      \
             -t tdm/wrf-populate docker


