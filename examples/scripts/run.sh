#!/usr/bin/env bash

set -euo pipefail

# Read in run specific details
source param/run.cfg

RUNID=${1:-2}
NUMPROC=${2:-2}
NUMTILES=${3:-1}
NUMSLOTS=${4:-1}


docker run --rm\
       --mount src=${RUNID},dst=/run\
       tdmproject/tdm-tools tdm wrf_configurator --target WRF\
       --config /run/wrf.yaml --ofile=/run/namelist.input\
       -D"geometry.geog_data_path=/geo/"\
       -D"@base.timespan.start.year=${YEAR}"\
       -D"@base.timespan.start.month=${MONTH}"\
       -D"@base.timespan.start.day=${DAY}"\
       -D"@base.timespan.start.hour=${HOUR}"\
       -D"@base.timespan.end.year=${YEAR}"\
       -D"@base.timespan.end.month=${MONTH}"\
       -D"@base.timespan.end.day=${DAY}"\
       -D"@base.timespan.end.hour=${END_HOUR}"\
       -D"running.parallel.numtiles=${NUMTILES}"

cat > hosts <<EOF
127.0.0.1 ${NUMSLOTS}
EOF

docker run --rm\
       --mount src=${RUNID},dst=/run\
       --mount type=bind,src=${PWD},dst=/src\
       alpine cp /src/hosts /run/hosts


docker run -it --rm\
       --mount src=${RUNID},dst=/run\
       tdm/wrf-wrf run_wrf /run ${NUMPROC} ${NUMTILES} /run/hosts
