#!/usr/bin/env bash

set -euo pipefail

function check_if_not_present () {
    VOLUME=$1
    SEMAPHORE="/foo/.__success__"
    CMD="alpine ls ${SEMAPHORE}"
    A=`docker run --rm --mount src=${VOLUME},dst=/foo ${CMD}`
    test "x$A" != x"${SEMAPHORE}"
}

# Read in run specific details
source ./param/run.cfg


if check_if_not_present ${GEOG_NAME} ; then 
    docker run --rm --mount source=${GEOG_NAME},destination=/geo \
           tdmproject/wrf-populate ${GEOG_NAME} /geo
fi


# FIXME first check if volume is already here
printf -v NOAADATA "noaa-%4d%02d%02d_%02d%02d-%s" \
       $YEAR $MONTH $DAY $HOUR 0 ${REQUESTED_RESOLUTION}

if check_if_not_present ${NOAADATA} ; then 
    docker run --rm\
       --mount src=${NOAADATA},dst=/gfs\
       tdmproject/tdm-tools \
       tdm gfs_fetch \
       --year ${YEAR} --month ${MONTH} --day ${DAY} --hour ${HOUR}\
       --target-directory /gfs/model_data\
       --semaphore-file /gfs/.__success__\
       --requested-resolution ${REQUESTED_RESOLUTION}
fi

RUNID=`date -u +"run-%F_%H-%M-%S"`
docker run --rm --mount src=${RUNID},dst=/run\
       --mount type=bind,src=${PWD}/param,dst=/src\
       alpine cp /src/Vtable /src/wrf.yaml /run

docker run --rm\
       --mount src=${RUNID},dst=/run\
       tdmproject/tdm-tools tdm wrf_configurator --target WPS\
       --config /run/wrf.yaml --ofile=/run/namelist.wps\
       -D"geometry.geog_data_path=/geo/"\
       -D"@base.timespan.start.year=${YEAR}"\
       -D"@base.timespan.start.month=${MONTH}"\
       -D"@base.timespan.start.day=${DAY}"\
       -D"@base.timespan.start.hour=${HOUR}"\
       -D"@base.timespan.end.year=${YEAR}"\
       -D"@base.timespan.end.month=${MONTH}"\
       -D"@base.timespan.end.day=${DAY}"\
       -D"@base.timespan.end.hour=${END_HOUR}"

docker run --rm\
       --mount src=${GEOG_NAME},dst=/geo\
       --mount src=${RUNID},dst=/run\
       tdmproject/wrf-wps run_geogrid /run


docker run --rm\
       --mount src=${NOAADATA},dst=/gfs\
       --mount src=${RUNID},dst=/run\
       tdmproject/tdm-tools \
       tdm link_grib --source-directory /gfs/model_data --target-directory /run

docker run --rm\
       --mount src=${GEOG_NAME},dst=/geo\
       --mount src=${NOAADATA},dst=/gfs\
       --mount src=${RUNID},dst=/run\
       tdmproject/wrf-wps run_ungrib /run

docker run --rm\
       --mount src=${GEOG_NAME},dst=/geo\
       --mount src=${NOAADATA},dst=/gfs\
       --mount src=${RUNID},dst=/run\
       tdmproject/wrf-wps run_metgrid /run

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
       -D"@base.timespan.end.hour=${END_HOUR}"

docker run --rm\
       --mount src=${RUNID},dst=/run\
       tdmproject/wrf-wrf run_real /run

echo "RUNID is ${RUNID}"
