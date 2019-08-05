#!/usr/bin/env bash

run_id=${1}
processes=${2:-1}
processes_per_worker=${3:-1}
# TODO: add options for np and npernode

# TODO: fixme using env var
run_path="/run_data/${run_id}"

if [[ ! -d ${run_path} ]]; then
  echo "Unable to find rundir '${run_path}'";
  exit 99
fi

cd "${run_path}" || exit

RUN_DETAILS_FILES="
aerosol.formatted aerosol_lat.formatted aerosol_lon.formatted aerosol_plev.formatted
bulkdens.asc_s_0_03_0_9 bulkradii.asc_s_0_03_0_9
CAM_ABS_DATA CAM_AEROPT_DATA
CAMtr_volume_mixing_ratio.A1B CAMtr_volume_mixing_ratio.A2
CAMtr_volume_mixing_ratio.RCP4.5 CAMtr_volume_mixing_ratio.RCP6
CAMtr_volume_mixing_ratio.RCP8.5
capacity.asc
CCN_ACTIVATE.BIN CLM_ALB_ICE_DFS_DATA CLM_ALB_ICE_DRC_DATA
CLM_ASM_ICE_DFS_DATA CLM_ASM_ICE_DRC_DATA
CLM_DRDSDT0_DATA CLM_EXT_ICE_DFS_DATA CLM_EXT_ICE_DRC_DATA
CLM_KAPPA_DATA CLM_TAU_DATA
co2_trans coeff_p.asc coeff_q.asc constants.asc
ETAMPNEW_DATA ETAMPNEW_DATA_DBL ETAMPNEW_DATA.expanded_rain
ETAMPNEW_DATA.expanded_rain_DBL
GENPARM.TBL grib2map.tbl gribmap.txt
kernels.asc_s_0_03_0_9 kernels_z.asc
LANDUSE.TBL
masses.asc
MPTABLE.TBL
ozone.formatted ozone_lat.formatted ozone_plev.formatted
p3_lookup_table_1.dat
RRTM_DATA RRTM_DATA_DBL RRTMG_LW_DATA RRTMG_LW_DATA_DBL
RRTMG_SW_DATA RRTMG_SW_DATA_DBL SOILPARM.TBL
termvels.asc
tr49t67
tr49t85
tr67t85
URBPARM.TBL
URBPARM_UZE.TBL
VEGPARM.TBL
wind-turbine-1.tbl
"

for f in ${RUN_DETAILS_FILES}
do
    rm -rf ./$f
    ln -sf /wrf/WRF/run/$f .
done
ln -sf /wrf/WRF/run/wrf.exe .


mpiexec --allow-run-as-root --prefix /usr/lib64/openmpi -mca btl ^openib \
          --hostfile /kube-openmpi/generated/hostfile \
          -v --display-map -np ${processes} -npernode ${processes_per_worker} \
          wrf.exe
