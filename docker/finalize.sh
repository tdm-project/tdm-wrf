#!/bin/bash

set -e pipefail

RUN_DATA=${RUN_DATA:-"/run"}
GEO_DATA=${GEO_DATA:-"/geo"}
GFS_DATA=${GFS_DATA:-"/gfs/model_data"}

tdm wrf_configurator --target WPS \
       --config ${RUN_DATA}/wrf.yaml --ofile=${RUN_DATA}/namelist.wps  \
       -D"geometry.geog_data_path=${GEO_DATA}"\
       -D"@base.timespan.start.year=${YEAR}"\
       -D"@base.timespan.start.month=${MONTH}"\
       -D"@base.timespan.start.day=${DAY}"\
       -D"@base.timespan.start.hour=${HOUR}"\
       -D"@base.timespan.end.year=${YEAR}"\
       -D"@base.timespan.end.month=${MONTH}"\
       -D"@base.timespan.end.day=${DAY}"\
       -D"@base.timespan.end.hour=${END_HOUR}"

run_geogrid ${RUN_DATA}

tdm link_grib --source-directory ${GFS_DATA} --target-directory ${RUN_DATA}

run_ungrib ${RUN_DATA}

run_metgrid ${RUN_DATA}

tdm wrf_configurator --target WRF\
       --config ${RUN_DATA}/wrf.yaml --ofile=${RUN_DATA}/namelist.input\
       -D"geometry.geog_data_path=${GEO_DATA}"\
       -D"@base.timespan.start.year=${YEAR}"\
       -D"@base.timespan.start.month=${MONTH}"\
       -D"@base.timespan.start.day=${DAY}"\
       -D"@base.timespan.start.hour=${HOUR}"\
       -D"@base.timespan.end.year=${YEAR}"\
       -D"@base.timespan.end.month=${MONTH}"\
       -D"@base.timespan.end.day=${DAY}"\
       -D"@base.timespan.end.hour=${END_HOUR}"

run_real ${RUN_DATA}