#!/usr/bin/env bash

# Copyright 2018-2019 CRS4 (http://www.crs4.it/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RUN_DATA=${1:-"/data/run"}
LINK_DETAILS=${2:-"/data/config/details-files"}

if [[ ! -d ${RUN_DATA} ]]; then
    "RUN_DATA folder '${RUN_DATA}' doesn't exit!!!"
    exit 99
fi

if [[ ! -e ${LINK_DETAILS} ]]; then
    "File '${LINK_DETAILS}' containing links-details  doesn't exit!!!"
    exit 99
fi

cd ${RUN_DATA}
for f in $(cat ${LINK_DETAILS})
do
    rm -rf ./$f
    ln -sf /wrf/WRF/run/$f .
done
ln -sf /wrf/WRF/run/wrf.exe .
