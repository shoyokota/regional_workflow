#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHDIR/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u -x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs a analysis with FV3 for the
specified cycle.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.
# Then process the arguments provided to this script/function (which 
# should consist of a set of name-value pairs of the form arg1="value1",
# etc).
#
#-----------------------------------------------------------------------
#
valid_args=( "cycle_dir" "cycle_type" "gsi_type" "mem_type" "analworkdir" \
             "observer_nwges_dir" "slash_ensmem_subdir" "comout" \
             "rrfse_fg_root" "satbias_dir" "ob_type" "gridspec_dir" )
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
# Load modules.
#
#-----------------------------------------------------------------------
#
case $MACHINE in
#
"WCOSS_C" | "WCOSS")
#
  module load NCO/4.7.0
  module list
  ulimit -s unlimited
  ulimit -a
  APRUN="mpirun -l"
  ;;
#
"WCOSS_DELL_P3")
#
  module load NCO/4.7.0
  module list
  ulimit -s unlimited
  ulimit -a
  APRUN="mpirun -l"
  IO_LAYOUT_Y_IN=${IO_LAYOUT_Y}
  ;;
#
"THEIA")
#
  ulimit -s unlimited
  ulimit -a
  np=${SLURM_NTASKS}
  APRUN="mpirun"
  IO_LAYOUT_Y_IN=${IO_LAYOUT_Y}
  ;;
#
"HERA")
  ulimit -s unlimited
  ulimit -a
  export OMP_NUM_THREADS=1
  export OMP_STACKSIZE=300M
  APRUN="srun"
  IO_LAYOUT_Y_IN=${IO_LAYOUT_Y}
  ;;
#
"ORION")
  ulimit -s unlimited
  ulimit -a
  export OMP_NUM_THREADS=1
  export OMP_STACKSIZE=1024M
  APRUN="srun"
  IO_LAYOUT_Y_IN=1
  ;;
#
"JET")
  export OMP_NUM_THREADS=2
  export OMP_STACKSIZE=1024M
  ulimit -s unlimited
  ulimit -a
  APRUN="srun"
  IO_LAYOUT_Y_IN=${IO_LAYOUT_Y}
  ;;
#
"ODIN")
#
  module list

  ulimit -s unlimited
  ulimit -a
  APRUN="srun"
  IO_LAYOUT_Y_IN=${IO_LAYOUT_Y}
  ;;
#
esac
#
#-----------------------------------------------------------------------
#
# Extract from CDATE the starting year, month, day, and hour of the
# forecast.  These are needed below for various operations.
#
#-----------------------------------------------------------------------
#
START_DATE=$(echo "${CDATE}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')

YYYYMMDDHH=$(date +%Y%m%d%H -d "${START_DATE}")
JJJ=$(date +%j -d "${START_DATE}")

YYYY=${YYYYMMDDHH:0:4}
MM=${YYYYMMDDHH:4:2}
DD=${YYYYMMDDHH:6:2}
HH=${YYYYMMDDHH:8:2}
YYYYMMDD=${YYYYMMDDHH:0:8}
#
# YYYY-MM-DD_meso_uselist.txt and YYYYMMDD_rejects.txt:
# both contain past 7 day OmB averages till ~YYYYMMDD_23:59:59 UTC
# So they are to be used by next day cycles
MESO_USELIST_FN=$(date +%Y-%m-%d -d "${START_DATE} -1 day")_meso_uselist.txt
AIR_REJECT_FN=$(date +%Y%m%d -d "${START_DATE} -1 day")_rejects.txt
#
#-----------------------------------------------------------------------
#
# go to working directory.
# define fix and background path
#
#-----------------------------------------------------------------------

cd_vrfy ${analworkdir}

fixgriddir=$FIX_GSI/${PREDEF_GRID_NAME}
if [ ${cycle_type} == "spinup" ]; then
  if [ ${mem_type} == "MEAN" ]; then
    bkpath=${cycle_dir}/ensmean/fcst_fv3lam_spinup/INPUT
  else
    bkpath=${cycle_dir}${slash_ensmem_subdir}/fcst_fv3lam_spinup/INPUT
  fi
else
  if [ ${mem_type} == "MEAN" ]; then
    bkpath=${cycle_dir}/ensmean/fcst_fv3lam/INPUT
  else
    bkpath=${cycle_dir}${slash_ensmem_subdir}/fcst_fv3lam/INPUT
  fi
fi
# decide background type
if [ -r "${bkpath}/coupler.res" ]; then
  BKTYPE=0              # warm start
else
  BKTYPE=1              # cold start
fi

if  [ ${ob_type} != "conv" ]; then #not using GDAS
  l_both_fv3sar_gfs_ens=.false.
fi

#---------------------------------------------------------------------
#
# decide regional_ensemble_option: global ensemble (1) or FV3LAM ensemble (5)
#
#---------------------------------------------------------------------
#
echo "regional_ensemble_option is ",${regional_ensemble_option:-1}

print_info_msg "$VERBOSE" "FIX_GSI is $FIX_GSI"
print_info_msg "$VERBOSE" "fixgriddir is $fixgriddir"
print_info_msg "$VERBOSE" "default bkpath is $bkpath"
print_info_msg "$VERBOSE" "background type is is $BKTYPE"

#
# Check if we have enough FV3-LAM ensembles when regional_ensemble_option=5
#
if  [[ ${regional_ensemble_option:-1} -eq 5 ]]; then
  ens_nstarthr=$( printf "%02d" ${DA_CYCLE_INTERV} )
  imem=1
  ifound=0
  while [[ $imem -le ${NUM_ENS_MEMBERS} ]];do
    memcharv0=$( printf "%03d" $imem )
    memchar=mem$( printf "%04d" $imem )

    YYYYMMDDHHmInterv=$( date +%Y%m%d%H -d "${START_DATE} ${DA_CYCLE_INTERV} hours ago" )
    restart_prefix="${YYYYMMDD}.${HH}0000."
    slash_ensmem_subdir=$memchar
    bkpathmem=${rrfse_fg_root}/${YYYYMMDDHHmInterv}/${slash_ensmem_subdir}/fcst_fv3lam/RESTART
    if [ ! -d "${bkpathmem}" ] ; then
      bkpathmem=${rrfse_fg_root}/${YYYYMMDDHHmInterv}/${slash_ensmem_subdir}/fcst_fv3lam_spinup/RESTART
    fi

    dynvarfile=${bkpathmem}/${restart_prefix}fv_core.res.tile1.nc
    tracerfile=${bkpathmem}/${restart_prefix}fv_tracer.res.tile1.nc
    phyvarfile=${bkpathmem}/${restart_prefix}phy_data.nc
    if [ -r "${dynvarfile}" ] && [ -r "${tracerfile}" ] && [ -r "${phyvarfile}" ] ; then
      ln_vrfy -snf ${bkpathmem}/${restart_prefix}fv_core.res.tile1.nc       fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_dynvars
      ln_vrfy -snf ${bkpathmem}/${restart_prefix}fv_tracer.res.tile1.nc     fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_tracer
      ln_vrfy -snf ${bkpathmem}/${restart_prefix}phy_data.nc                fv3SAR${ens_nstarthr}_ens_mem${memcharv0}-fv3_phyvars
      (( ifound += 1 ))
    else
      print_info_msg "Error: cannot find ensemble files: ${dynvarfile} ${tracerfile} ${phyvarfile} "
    fi
    (( imem += 1 ))
  done
  if [[ $ifound -ne ${NUM_ENS_MEMBERS} ]]; then
    print_info_msg "Not enough FV3_LAM ensembles, will fall to GDAS"
    regional_ensemble_option=1
    l_both_fv3sar_gfs_ens=.false.
  fi
fi
#
if  [[ ${regional_ensemble_option:-1} -eq 1 || ${l_both_fv3sar_gfs_ens} = ".true." ]]; then #using GDAS
  #-----------------------------------------------------------------------
  # Make a list of the latest GFS EnKF ensemble
  #-----------------------------------------------------------------------
  stampcycle=$(date -d "${START_DATE}" +%s)
  minHourDiff=100
  loops="009"    # or 009s for GFSv15
  ftype="nc"  # or nemsio for GFSv15
  foundgdasens="false"
  cat "no ens found" >> filelist03

  case $MACHINE in

  "WCOSS_C" | "WCOSS" | "WCOSS_DELL_P3")

    for loop in $loops; do
      for timelist in $(ls ${ENKF_FCST}/enkfgdas.*/*/atmos/mem080/gdas*.atmf${loop}.${ftype}); do
        availtimeyyyymmdd=$(echo ${timelist} | cut -d'/' -f9 | cut -c 10-17)
        availtimehh=$(echo ${timelist} | cut -d'/' -f10)
        availtime=${availtimeyyyymmdd}${availtimehh}
        avail_time=$(echo "${availtime}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
        avail_time=$(date -d "${avail_time}")

        stamp_avail=$(date -d "${avail_time} ${loop} hours" +%s)

        hourDiff=$(echo "($stampcycle - $stamp_avail) / (60 * 60 )" | bc);
        if [[ ${stampcycle} -lt ${stamp_avail} ]]; then
           hourDiff=$(echo "($stamp_avail - $stampcycle) / (60 * 60 )" | bc);
        fi

        if [[ ${hourDiff} -lt ${minHourDiff} ]]; then
           minHourDiff=${hourDiff}
           enkfcstname=gdas.t${availtimehh}z.atmf${loop}
           eyyyymmdd=$(echo ${availtime} | cut -c1-8)
           ehh=$(echo ${availtime} | cut -c9-10)
           foundgdasens="true"
        fi
      done
    done

    if [ ${foundgdasens} = "true" ]
    then
      ls ${ENKF_FCST}/enkfgdas.${eyyyymmdd}/${ehh}/atmos/mem???/${enkfcstname}.nc > filelist03
    fi

    ;;
  "JET" | "HERA" | "ORION" )

    for loop in $loops; do
      for timelist in $(ls ${ENKF_FCST}/*.gdas.t*z.atmf${loop}.mem080.${ftype}); do
        availtimeyy=$(basename ${timelist} | cut -c 1-2)
        availtimeyyyy=20${availtimeyy}
        availtimejjj=$(basename ${timelist} | cut -c 3-5)
        availtimemm=$(date -d "${availtimeyyyy}0101 +$(( 10#${availtimejjj} - 1 )) days" +%m)
        availtimedd=$(date -d "${availtimeyyyy}0101 +$(( 10#${availtimejjj} - 1 )) days" +%d)
        availtimehh=$(basename ${timelist} | cut -c 6-7)
        availtime=${availtimeyyyy}${availtimemm}${availtimedd}${availtimehh}
        avail_time=$(echo "${availtime}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
        avail_time=$(date -d "${avail_time}")

        stamp_avail=$(date -d "${avail_time} ${loop} hours" +%s)

        hourDiff=$(echo "($stampcycle - $stamp_avail) / (60 * 60 )" | bc);
        if [[ ${stampcycle} -lt ${stamp_avail} ]]; then
           hourDiff=$(echo "($stamp_avail - $stampcycle) / (60 * 60 )" | bc);
        fi

        if [[ ${hourDiff} -lt ${minHourDiff} ]]; then
           minHourDiff=${hourDiff}
           enkfcstname=${availtimeyy}${availtimejjj}${availtimehh}00.gdas.t${availtimehh}z.atmf${loop}
           foundgdasens="true"
        fi
      done
    done

    if [ $foundgdasens = "true" ]; then
      ls ${ENKF_FCST}/${enkfcstname}.mem0??.${ftype} >> filelist03
    fi

  esac
fi

#
#-----------------------------------------------------------------------
#
# set default values for namelist
#
#-----------------------------------------------------------------------

ifsatbufr=.false.
ifsoilnudge=.false.
ifhyb=.false.
miter=2
niter1=50
niter2=50
lread_obs_save=.false.
lread_obs_skip=.false.
if_model_dbz=.false.
nummem_gfs=0
nummem_fv3sar=0

# Determine if hybrid option is available
memname='atmf009'

if [ ${regional_ensemble_option:-1} -eq 5 ]  && [ ${BKTYPE} != 1  ]; then 
  if [ ${l_both_fv3sar_gfs_ens} = ".true." ]; then
    nummem_gfs=$(more filelist03 | wc -l)
    nummem_gfs=$((nummem_gfs - 3 ))
  else
    weight_ens_gfs=1.0
    weight_ens_fv3sar=1.0
  fi
  nummem_fv3sar=$NUM_ENS_MEMBERS
  nummem=`expr ${nummem_gfs} + ${nummem_fv3sar}`
  print_info_msg "$VERBOSE" "Do hybrid with FV3LAM ensemble"
  ifhyb=.true.
  print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI hybrid uses FV3LAM ensemble with n_ens=${nummem}" 
  grid_ratio_ens="1"
  ens_fast_read=.true.
else    
  weight_ens_gfs=1.0
  weight_ens_fv3sar=1.0
  nummem_gfs=$(more filelist03 | wc -l)
  nummem_gfs=$((nummem_gfs - 3 ))
  nummem=${nummem_gfs}
  if [[ ${nummem} -ge ${HYBENSMEM_NMIN} ]]; then
    print_info_msg "$VERBOSE" "Do hybrid with ${memname}"
    ifhyb=.true.
    print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI hybrid uses ${memname} with n_ens=${nummem}"
  else
    print_info_msg "$VERBOSE" " Cycle ${YYYYMMDDHH}: GSI does pure 3DVAR."
    print_info_msg "$VERBOSE" " Hybrid needs at least ${HYBENSMEM_NMIN} ${memname} ensembles, only ${nummem} available"
  fi
  if [[ ${ob_type} == "all" ]]; then
    ob_type="conv"
  fi
  l_mgbf_loc=.false.
  ens_h="82.1580"
  ens_v="3"
  nsclgrp=1
  ngvarloc=1
fi

#
#-----------------------------------------------------------------------
#
# link or copy background and grib configuration files
#
#  Using ncks to add phis (terrain) into cold start input background.
#           it is better to change GSI to use the terrain from fix file.
#  Adding radar_tten array to fv3_tracer. Should remove this after add this array in
#           radar_tten converting code.
#-----------------------------------------------------------------------

n_iolayouty=$(($IO_LAYOUT_Y_IN-1))
list_iolayout=$(seq 0 $n_iolayouty)

ln_vrfy -snf ${fixgriddir}/fv3_akbk                     fv3_akbk
ln_vrfy -snf ${fixgriddir}/fv3_grid_spec                fv3_grid_spec

if [ ${BKTYPE} -eq 1 ]; then  # cold start uses background from INPUT
  if [ -r "${bkpath}/bk_${ob_type}_gfs_data.tile7.halo0.nc" ]; then
    cp_vrfy -f ${bkpath}/bk_${ob_type}_sfc_data.tile7.halo0.nc   ${bkpath}/sfc_data.tile7.halo0.nc
    cp_vrfy -f ${bkpath}/bk_${ob_type}_gfs_data.tile7.halo0.nc   ${bkpath}/gfs_data.tile7.halo0.nc
  else
    cp_vrfy ${bkpath}/sfc_data.tile7.halo0.nc  ${bkpath}/bk_${ob_type}_sfc_data.tile7.halo0.nc
    cp_vrfy ${bkpath}/gfs_data.tile7.halo0.nc  ${bkpath}/bk_${ob_type}_gfs_data.tile7.halo0.nc
  fi
  ln_vrfy -snf ${fixgriddir}/phis.nc               phis.nc
  ncks -A -v  phis               phis.nc           ${bkpath}/gfs_data.tile7.halo0.nc 

  ln_vrfy -snf ${bkpath}/sfc_data.tile7.halo0.nc   fv3_sfcdata
  ln_vrfy -snf ${bkpath}/gfs_data.tile7.halo0.nc   fv3_dynvars
  ln_vrfy -s fv3_dynvars                           fv3_tracer

  fv3lam_bg_type=1
else                          # cycle uses background from restart
  if [ "${IO_LAYOUT_Y_IN}" == "1" ]; then
    if [ -r "${bkpath}/bk_${ob_type}_fv_core.res.tile1.nc" ]; then
      cp_vrfy -f ${bkpath}/bk_${ob_type}_fv_core.res.tile1.nc     ${bkpath}/fv_core.res.tile1.nc
      cp_vrfy -f ${bkpath}/bk_${ob_type}_fv_tracer.res.tile1.nc   ${bkpath}/fv_tracer.res.tile1.nc
      cp_vrfy -f ${bkpath}/bk_${ob_type}_sfc_data.nc              ${bkpath}/sfc_data.nc
      cp_vrfy -f ${bkpath}/bk_${ob_type}_phy_data.nc              ${bkpath}/phy_data.nc
    else
      cp_vrfy ${bkpath}/fv_core.res.tile1.nc     ${bkpath}/bk_${ob_type}_fv_core.res.tile1.nc
      cp_vrfy ${bkpath}/fv_tracer.res.tile1.nc   ${bkpath}/bk_${ob_type}_fv_tracer.res.tile1.nc
      cp_vrfy ${bkpath}/sfc_data.nc              ${bkpath}/bk_${ob_type}_sfc_data.nc
      cp_vrfy ${bkpath}/phy_data.nc              ${bkpath}/bk_${ob_type}_phy_data.nc
    fi
    ln_vrfy  -snf ${bkpath}/fv_core.res.tile1.nc             fv3_dynvars
    ln_vrfy  -snf ${bkpath}/fv_tracer.res.tile1.nc           fv3_tracer
    ln_vrfy  -snf ${bkpath}/sfc_data.nc                      fv3_sfcdata
    ln_vrfy  -snf ${bkpath}/phy_data.nc                      fv3_phyvars
  else
    for ii in ${list_iolayout}
    do
      iii=`printf %4.4i $ii`
      ln_vrfy  -snf ${bkpath}/fv_core.res.tile1.nc.${iii}     fv3_dynvars.${iii}
      ln_vrfy  -snf ${bkpath}/fv_tracer.res.tile1.nc.${iii}   fv3_tracer.${iii}
      ln_vrfy  -snf ${bkpath}/sfc_data.nc.${iii}              fv3_sfcdata.${iii}
      ln_vrfy  -snf ${bkpath}/phy_data.nc.${iii}              fv3_phyvars.${iii}
      ln_vrfy  -snf ${gridspec_dir}/fv3_grid_spec.${iii}      fv3_grid_spec.${iii}
    done
  fi
  fv3lam_bg_type=0
fi

# update times in coupler.res to current cycle time
cp_vrfy ${fixgriddir}/fv3_coupler.res          coupler.res
sed -i "s/yyyy/${YYYY}/" coupler.res
sed -i "s/mm/${MM}/"     coupler.res
sed -i "s/dd/${DD}/"     coupler.res
sed -i "s/hh/${HH}/"     coupler.res

#
#-----------------------------------------------------------------------
#
# link observation files
# copy observation files to working directory 
#
#-----------------------------------------------------------------------
if [[ "${NET}" = "RTMA"* ]]; then
  SUBH=$(date +%M -d "${START_DATE}")
  obs_source="rtma_ru"
  obsfileprefix=${obs_source}
  obspath_tmp=${OBSPATH}/${obs_source}.${YYYYMMDD}

else
  SUBH=""
  obs_source=rap
  if [ ${HH} -eq '00' ] || [ ${HH} -eq '12' ]; then
    obs_source=rap_e
  fi

  case $MACHINE in

  "WCOSS_C" | "WCOSS" | "WCOSS_DELL_P3")
     obsfileprefix=${obs_source}
     obspath_tmp=${OBSPATH}/${obs_source}.${YYYYMMDD}
    ;;
  "JET" | "HERA")
     obsfileprefix=${YYYYMMDDHH}.${obs_source}
     obspath_tmp=${OBSPATH}
    ;;
  "ORION" )
     obs_source=rap
     obsfileprefix=${YYYYMMDDHH}.${obs_source}               # rap observation from JET.
     #obsfileprefix=${obs_source}.${YYYYMMDD}/${obs_source}    # observation from operation.
     obspath_tmp=${OBSPATH}
    ;;
  *)
     obsfileprefix=${obs_source}
     obspath_tmp=${OBSPATH}
  esac
fi

if [[ ${gsi_type} == "OBSERVER" || ${ob_type} == "conv" || ${ob_type} == "all" ]]; then

  obs_files_source[0]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.prepbufr.tm00
  obs_files_target[0]=prepbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.satwnd.tm00.bufr_d
  obs_files_target[${obs_number}]=satwndbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}${SUBH}z.nexrad.tm00.bufr_d
  obs_files_target[${obs_number}]=l2rwbufr

  if [[ ${DO_ENKF_RADAR_REF} == "TRUE" || ${ob_type} == "all" ]]; then
    obs_number=${#obs_files_source[@]}
    if [ ${cycle_type} == "spinup" ]; then
      obs_files_source[${obs_number}]=${cycle_dir}/process_radarref_spinup/00/Gridded_ref.nc
    else
      obs_files_source[${obs_number}]=${cycle_dir}/process_radarref/00/Gridded_ref.nc
    fi
    obs_files_target[${obs_number}]=dbzobs.nc
  fi

else

  if [ ${ob_type} == "radardbz" ]; then

    if [ ${cycle_type} == "spinup" ]; then
      obs_files_source[0]=${cycle_dir}/process_radarref_spinup/00/Gridded_ref.nc
    else
      obs_files_source[0]=${cycle_dir}/process_radarref/00/Gridded_ref.nc
    fi
    obs_files_target[0]=dbzobs.nc

  fi

fi

#
#-----------------------------------------------------------------------
#
# including satellite radiance data
#
#-----------------------------------------------------------------------
if [ ${DO_RADDA} == "TRUE" ]; then

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.1bamua.tm00.bufr_d
  obs_files_target[${obs_number}]=amsuabufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esamua.tm00.bufr_d
  obs_files_target[${obs_number}]=amsuabufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.1bmhs.tm00.bufr_d
  obs_files_target[${obs_number}]=mhsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esmhs.tm00.bufr_d
  obs_files_target[${obs_number}]=mhsbufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.atms.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esatms.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.atmsdb.tm00.bufr_d
  obs_files_target[${obs_number}]=atmsbufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.crisf4.tm00.bufr_d
  obs_files_target[${obs_number}]=crisfsbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.crsfdb.tm00.bufr_d
  obs_files_target[${obs_number}]=crisfsbufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.mtiasi.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.esiasi.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufrears

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.iasidb.tm00.bufr_d
  obs_files_target[${obs_number}]=iasibufr_db

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.gsrcsr.tm00.bufr_d
  obs_files_target[${obs_number}]=abibufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.ssmisu.tm00.bufr_d
  obs_files_target[${obs_number}]=ssmisbufr

  obs_number=${#obs_files_source[@]}
  obs_files_source[${obs_number}]=${obspath_tmp}/${obsfileprefix}.t${HH}z.sevcsr.tm00.bufr_d
  obs_files_target[${obs_number}]=sevcsr

fi

obs_number=${#obs_files_source[@]}
for (( i=0; i<${obs_number}; i++ ));
do
  obs_file=${obs_files_source[$i]}
  obs_file_t=${obs_files_target[$i]}
  if [ -r "${obs_file}" ]; then
    ln -s "${obs_file}" "${obs_file_t}"
  else
    print_info_msg "$VERBOSE" "Warning: ${obs_file} does not exist!"
  fi
done

#
#-----------------------------------------------------------------------
#
# Create links to fix files in the FIXgsi directory.
# Set fixed files
#   berror   = forecast model background error statistics
#   specoef  = CRTM spectral coefficients
#   trncoef  = CRTM transmittance coefficients
#   emiscoef = CRTM coefficients for IR sea surface emissivity model
#   aerocoef = CRTM coefficients for aerosol effects
#   cldcoef  = CRTM coefficients for cloud effects
#   satinfo  = text file with information about assimilation of brightness temperatures
#   satangl  = angle dependent bias correction file (fixed in time)
#   pcpinfo  = text file with information about assimilation of prepcipitation rates
#   ozinfo   = text file with information about assimilation of ozone data
#   errtable = text file with obs error for conventional data (regional only)
#   convinfo = text file with information about assimilation of conventional data
#   bufrtable= text file ONLY needed for single obs test (oneobstest=.true.)
#   bftab_sst= bufr table for sst ONLY needed for sst retrieval (retrieval=.true.)
#
#-----------------------------------------------------------------------

ANAVINFO=${FIX_GSI}/${ANAVINFO_FN}
if [ ${DO_ENKF_RADAR_REF} == "TRUE" ]; then
  ANAVINFO=${FIX_GSI}/${ANAVINFO_DBZ_FN}
  diag_radardbz=.true.
  beta1_inv=0.0
  if_model_dbz=.true.
fi
if [[ ${gsi_type} == "ANALYSIS" && ${ob_type} == "radardbz" ]]; then
  ANAVINFO=${FIX_GSI}/${ENKF_ANAVINFO_DBZ_FN}
  miter=1
  niter1=100
  niter2=0
  bkgerr_vs=0.1
  bkgerr_hzscl="0.4,0.5,0.6"
  beta1_inv=0.0
  readin_localization=.false.
  ens_h=${ens_h_radardbz}
  ens_v=${ens_v_radardbz}
  nsclgrp=1
  ngvarloc=1
  r_ensloccov4tim=0
  r_ensloccov4var=0
  r_ensloccov4scl=0
  q_hyb_ens=.true.
  if_model_dbz=.true.
  l_mgbf_loc=.false.
fi
if [[ ${gsi_type} == "ANALYSIS" && ${ob_type} == "all" ]]; then
  ANAVINFO=${FIX_GSI}/${ANAVINFO_ALL_FN}
  if_model_dbz=.true.
fi
naensloc=`expr ${nsclgrp} \* ${ngvarloc} + ${nsclgrp} - 1`
CONVINFO=${FIX_GSI}/${CONVINFO_FN}
HYBENSINFO=${FIX_GSI}/${HYBENSINFO_FN}
OBERROR=${FIX_GSI}/${OBERROR_FN}
BERROR=${FIX_GSI}/${BERROR_FN}

SATINFO=${FIX_GSI}/global_satinfo.txt
OZINFO=${FIX_GSI}/global_ozinfo.txt
PCPINFO=${FIX_GSI}/global_pcpinfo.txt
ATMS_BEAMWIDTH=${FIX_GSI}/atms_beamwidth.txt

# Fixed fields
cp_vrfy ${ANAVINFO} anavinfo
cp_vrfy ${BERROR}   berror_stats
cp_vrfy $SATINFO    satinfo
cp_vrfy $CONVINFO   convinfo
cp_vrfy $OZINFO     ozinfo
cp_vrfy $PCPINFO    pcpinfo
cp_vrfy $OBERROR    errtable
cp_vrfy $ATMS_BEAMWIDTH atms_beamwidth.txt
cp_vrfy ${HYBENSINFO} hybens_info

# Get surface observation provider list
if [ -r ${FIX_GSI}/gsd_sfcobs_provider.txt ]; then
  cp_vrfy ${FIX_GSI}/gsd_sfcobs_provider.txt gsd_sfcobs_provider.txt
else
  print_info_msg "$VERBOSE" "Warning: gsd surface observation provider does not exist!" 
fi

# Get aircraft reject list
for reject_list in "${AIRCRAFT_REJECT}/current_bad_aircraft.txt" \
                   "${AIRCRAFT_REJECT}/${AIR_REJECT_FN}"
do
  if [ -r $reject_list ]; then
    cp_vrfy $reject_list current_bad_aircraft
    print_info_msg "$VERBOSE" "Use aircraft reject list: $reject_list "
    break
  fi
done
if [ ! -r $reject_list ] ; then 
  print_info_msg "$VERBOSE" "Warning: gsd aircraft reject list does not exist!" 
fi

# Get mesonet uselist
gsd_sfcobs_uselist="gsd_sfcobs_uselist.txt"
for use_list in "${SFCOBS_USELIST}/current_mesonet_uselist.txt" \
                "${SFCOBS_USELIST}/${MESO_USELIST_FN}"      \
                "${SFCOBS_USELIST}/gsd_sfcobs_uselist.txt"
do 
  if [ -r $use_list ] ; then
    cp_vrfy $use_list  $gsd_sfcobs_uselist
    print_info_msg "$VERBOSE" "Use surface obs uselist: $use_list "
    break
  fi
done
if [ ! -r $use_list ] ; then 
  print_info_msg "$VERBOSE" "Warning: gsd surface observation uselist does not exist!" 
fi

#-----------------------------------------------------------------------
#
# CRTM Spectral and Transmittance coefficients
#
#-----------------------------------------------------------------------
CRTMFIX=${FIX_CRTM}
emiscoef_IRwater=${CRTMFIX}/Nalli.IRwater.EmisCoeff.bin
emiscoef_IRice=${CRTMFIX}/NPOESS.IRice.EmisCoeff.bin
emiscoef_IRland=${CRTMFIX}/NPOESS.IRland.EmisCoeff.bin
emiscoef_IRsnow=${CRTMFIX}/NPOESS.IRsnow.EmisCoeff.bin
emiscoef_VISice=${CRTMFIX}/NPOESS.VISice.EmisCoeff.bin
emiscoef_VISland=${CRTMFIX}/NPOESS.VISland.EmisCoeff.bin
emiscoef_VISsnow=${CRTMFIX}/NPOESS.VISsnow.EmisCoeff.bin
emiscoef_VISwater=${CRTMFIX}/NPOESS.VISwater.EmisCoeff.bin
emiscoef_MWwater=${CRTMFIX}/FASTEM6.MWwater.EmisCoeff.bin
aercoef=${CRTMFIX}/AerosolCoeff.bin
cldcoef=${CRTMFIX}/CloudCoeff.bin

ln -s ${emiscoef_IRwater} Nalli.IRwater.EmisCoeff.bin
ln -s $emiscoef_IRice ./NPOESS.IRice.EmisCoeff.bin
ln -s $emiscoef_IRsnow ./NPOESS.IRsnow.EmisCoeff.bin
ln -s $emiscoef_IRland ./NPOESS.IRland.EmisCoeff.bin
ln -s $emiscoef_VISice ./NPOESS.VISice.EmisCoeff.bin
ln -s $emiscoef_VISland ./NPOESS.VISland.EmisCoeff.bin
ln -s $emiscoef_VISsnow ./NPOESS.VISsnow.EmisCoeff.bin
ln -s $emiscoef_VISwater ./NPOESS.VISwater.EmisCoeff.bin
ln -s $emiscoef_MWwater ./FASTEM6.MWwater.EmisCoeff.bin
ln -s $aercoef  ./AerosolCoeff.bin
ln -s $cldcoef  ./CloudCoeff.bin


# Copy CRTM coefficient files based on entries in satinfo file
for file in $(awk '{if($1!~"!"){print $1}}' ./satinfo | sort | uniq) ;do
   ln -s ${CRTMFIX}/${file}.SpcCoeff.bin ./
   ln -s ${CRTMFIX}/${file}.TauCoeff.bin ./
done

#-----------------------------------------------------------------------
#
# cycling radiance bias corretion files
#
#-----------------------------------------------------------------------
if [ ${DO_RADDA} == "TRUE" ]; then
  if [ ${cycle_type} == "spinup" ]; then
    echo "spin up cycle"
    spinup_or_prod_rrfs=spinup
    for cyc_start in "${CYCL_HRS_SPINSTART[@]}"; do
      if [ ${HH} -eq ${cyc_start} ]; then
        spinup_or_prod_rrfs=prod 
      fi
    done
  else 
    echo " product cycle"
    spinup_or_prod_rrfs=prod
    for cyc_start in "${CYCL_HRS_PRODSTART[@]}"; do
      if [ ${HH} -eq ${cyc_start} ]; then
        spinup_or_prod_rrfs=spinup      
      fi 
    done
  fi

  satcounter=1
  maxcounter=240
  while [ $satcounter -lt $maxcounter ]; do
    SAT_TIME=`date +"%Y%m%d%H" -d "${START_DATE}  ${satcounter} hours ago"`
    echo $SAT_TIME
    if [ -r ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ]; then
      echo " using satellite bias files from ${SAT_TIME}"

      cp_vrfy ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias ./satbias_in
      cp_vrfy ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_satbias_pc ./satbias_pc
      cp_vrfy ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${SAT_TIME}_radstat ./radstat.rrfs

      break
    fi
    satcounter=` expr $satcounter + 1 `
  done

  ## if satbias files (go back to previous 10 dyas) are not available from ${satbias_dir}, use satbias files from the ${FIX_GSI} 
  if [ $satcounter -eq $maxcounter ]; then
    if [ -r ${FIX_GSI}/rrfs.gdas_satbias ]; then
      echo "using satllite gdas satbias_in files from ${FIX_GSI}"
      cp_vrfy ${FIX_GSI}/rrfs.gdas_satbias ./satbias_in
    fi
    if [ -r ${FIX_GSI}/rrfs.gdas_satbias_pc ]; then
      echo "using satllite gdas satbias_pc files from ${FIX_GSI}"
      cp_vrfy ${FIX_GSI}/rrfs.gdas_satbias_pc ./satbias_pc
    fi
    if [ -r ${FIX_GSI}/rrfs.gdas_radstat ]; then
      echo "using netcdf satllite radstat files from ${FIX_GSI}"
      cp_vrfy ${FIX_GSI}/rrfs.gdas_radstat ./radstat.rrfs
    fi
  fi

  listdiag=`tar xvf radstat.rrfs | cut -d' ' -f2 | grep _ges`
  for type in $listdiag; do
    diag_file=`echo $type | cut -d',' -f1`
    fname=`echo $diag_file | cut -d'.' -f1`
    date=`echo $diag_file | cut -d'.' -f2`
    gunzip $diag_file
    fnameanl=$(echo $fname|sed 's/_ges//g')
    mv $fname.$date* $fnameanl
  done
fi

#-----------------------------------------------------------------------
#
# Build the GSI namelist on-the-fly
#    most configurable paramters take values from settings in config.sh
#                                             (var_defns.sh in runtime)
#
#-----------------------------------------------------------------------
# 
if [ ${gsi_type} == "OBSERVER" ]; then
  miter=0
  ifhyb=.false.
  if [ ${mem_type} == "MEAN" ]; then
    lread_obs_save=.true.
    lread_obs_skip=.false.
  else
    lread_obs_save=.false.
    lread_obs_skip=.true.
    ln -s ../../ensmean/observer_gsi/obs_input.* .
  fi
  l_mgbf_loc=.false.
fi
if [ ${BKTYPE} -eq 1 ]; then
  n_iolayouty=1
else
  n_iolayouty=$(($IO_LAYOUT_Y_IN))
fi

if [ ${l_mgbf_loc} = ".true." ]; then
  cp_vrfy ${FIX_GSI}/mgbf_loc_${ob_type}/mgbf_loc*.nml .
fi
if [ ${BKTYPE} -eq 0 ] && [ ${gsi_type} == "ANALYSIS" ] && [ ${ob_type} == "conv" -o ${ob_type} == "all" ]; then 
  grid_ratio_fv3=2.002
fi

. ${FIX_GSI}/gsiparm.anl.sh
cat << EOF > gsiparm.anl
$gsi_namelist
EOF

#
#-----------------------------------------------------------------------
#
# Copy the GSI executable to the run directory.
#
#-----------------------------------------------------------------------
#
gsi_exec="${EXECDIR}/gsi.x"

if [ -f $gsi_exec ]; then
  print_info_msg "$VERBOSE" "
Copying the GSI executable to the run directory..."
  cp_vrfy ${gsi_exec} ${analworkdir}/gsi.x
else
  print_err_msg_exit "\
The GSI executable specified in GSI_EXEC does not exist:
  GSI_EXEC = \"$gsi_exec\"
Build GSI and rerun."
fi
#
#-----------------------------------------------------------------------
#
# Set and export variables.
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Run the GSI.  Note that we have to launch the forecast from
# the current cycle's run directory because the GSI executable will look
# for input files in the current directory.
#
#-----------------------------------------------------------------------
#
# comment out for testing
$APRUN -n 735 ./gsi.x < gsiparm.anl > stdout 2>&1 || print_err_msg_exit "\
Call to executable to run GSI returned with nonzero exit code."
#
#-----------------------------------------------------------------------
#
# touch a file "gsi_complete.txt" after the successful GSI run. This is to inform
# the successful analysis for the EnKF recentering
#
#-----------------------------------------------------------------------
#
touch gsi_complete.txt
if [[ ${ob_type} == "radardbz" || ${ob_type} == "all" ]]; then
  touch gsi_complete_radar.txt # for nonvarcldanl
fi
#
#-----------------------------------------------------------------------
#
# Copy analysis results to INPUT for model forecast.
#
#-----------------------------------------------------------------------
#
#
#if [ ${BKTYPE} -eq 1 ]; then  # cold start, put analysis back to current INPUT 
#  cp_vrfy ${analworkdir}/fv3_dynvars                  ${bkpath}/gfs_data.tile7.halo0.nc
#  cp_vrfy ${analworkdir}/fv3_sfcdata                  ${bkpath}/sfc_data.tile7.halo0.nc
#else                          # cycling
#  cp_vrfy ${analworkdir}/fv3_dynvars             ${bkpath}/fv_core.res.tile1.nc
#  cp_vrfy ${analworkdir}/fv3_tracer              ${bkpath}/fv_tracer.res.tile1.nc
#  cp_vrfy ${analworkdir}/fv3_sfcdata             ${bkpath}/sfc_data.nc
#fi

#-----------------------------------------------------------------------
# Loop over first and last outer loops to generate innovation
# diagnostic files for indicated observation types (groups)
#
# NOTE:  Since we set miter=2 in GSI namelist SETUP, outer
#        loop 03 will contain innovations with respect to 
#        the analysis.  Creation of o-a innovation files
#        is triggered by write_diag(3)=.true.  The setting
#        write_diag(1)=.true. turns on creation of o-g
#        innovation files.
#-----------------------------------------------------------------------
#

netcdf_diag=${netcdf_diag:-".false."}
binary_diag=${binary_diag:-".true."}

loops="01 03"
for loop in $loops; do

case $loop in
  01) string=ges;;
  03) string=anl;;
   *) string=$loop;;
esac

#  Collect diagnostic files for obs types (groups) below
numfile_rad_bin=0
numfile_cnv=0
numfile_rad=0
if [ $binary_diag = ".true." ]; then
   listall="hirs2_n14 msu_n14 sndr_g08 sndr_g11 sndr_g11 sndr_g12 sndr_g13 sndr_g08_prep sndr_g11_prep sndr_g12_prep sndr_g13_prep sndrd1_g11 sndrd2_g11 sndrd3_g11 sndrd4_g11 sndrd1_g15 sndrd2_g15 sndrd3_g15 sndrd4_g15 sndrd1_g13 sndrd2_g13 sndrd3_g13 sndrd4_g13 hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 amsua_n18 amsua_n19 amsua_metop-a amsua_metop-b amsua_metop-c amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua imgr_g08 imgr_g11 imgr_g12 pcp_ssmi_dmsp pcp_tmi_trmm conv sbuv2_n16 sbuv2_n17 sbuv2_n18 omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 hirs4_metop-a mhs_n18 mhs_n19 mhs_metop-a mhs_metop-b mhs_metop-c amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 iasi_metop-a iasi_metop-b iasi_metop-c seviri_m08 seviri_m09 seviri_m10 seviri_m11 cris_npp atms_npp ssmis_f17 cris-fsr_npp cris-fsr_n20 atms_n20 abi_g16 abi_g17 radardbz"
   for type in $listall; do
      count=$(ls pe*.${type}_${loop} | wc -l)
      if [[ $count -gt 0 ]]; then
         $(cat pe*.${type}_${loop} > diag_${type}_${string}.${YYYYMMDDHH})
         echo "diag_${type}_${string}.${YYYYMMDDHH}" >> listrad_bin
         numfile_rad_bin=`expr ${numfile_rad_bin} + 1`
      fi
   done
fi

if [ $netcdf_diag = ".true." ]; then
   listall_cnv="conv_ps conv_q conv_t conv_uv conv_pw conv_rw conv_sst conv_dbz"
   listall_rad="hirs2_n14 msu_n14 sndr_g08 sndr_g11 sndr_g11 sndr_g12 sndr_g13 sndr_g08_prep sndr_g11_prep sndr_g12_prep sndr_g13_prep sndrd1_g11 sndrd2_g11 sndrd3_g11 sndrd4_g11 sndrd1_g15 sndrd2_g15 sndrd3_g15 sndrd4_g15 sndrd1_g13 sndrd2_g13 sndrd3_g13 sndrd4_g13 hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 amsua_n18 amsua_n19 amsua_metop-a amsua_metop-b amsua_metop-c amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua imgr_g08 imgr_g11 imgr_g12 pcp_ssmi_dmsp pcp_tmi_trmm conv sbuv2_n16 sbuv2_n17 sbuv2_n18 omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 hirs4_metop-a mhs_n18 mhs_n19 mhs_metop-a mhs_metop-b mhs_metop-c amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 iasi_metop-a iasi_metop-b iasi_metop-c seviri_m08 seviri_m09 seviri_m10 seviri_m11 cris_npp atms_npp ssmis_f17 cris-fsr_npp cris-fsr_n20 atms_n20 abi_g16"

   cat_exec="${EXECDIR}/nc_diag_cat.x"

   if [ -f $cat_exec ]; then
      print_info_msg "$VERBOSE" "
        Copying the nc_diag_cat executable to the run directory..."
      cp_vrfy ${cat_exec} ${analworkdir}/nc_diag_cat.x
   else
      print_err_msg_exit "\
        The nc_diag_cat executable specified in cat_exec does not exist:
        cat_exec = \"$cat_exec\"
        Build GSI and rerun."
   fi

   for type in $listall_cnv; do
      count=$(ls pe*.${type}_${loop}.nc4 | wc -l)
      if [[ $count -gt 0 ]]; then
         ${APRUN} ./nc_diag_cat.x -o diag_${type}_${string}.${YYYYMMDDHH}.nc4 pe*.${type}_${loop}.nc4
         gzip diag_${type}_${string}.${YYYYMMDDHH}.nc4*
         echo "diag_${type}_${string}.${YYYYMMDDHH}.nc4*" >> listcnv
         numfile_cnv=`expr ${numfile_cnv} + 1`
      fi
   done

   for type in $listall_rad; do
      count=$(ls pe*.${type}_${loop}.nc4 | wc -l)
      if [[ $count -gt 0 ]]; then
         ${APRUN} ./nc_diag_cat.x -o diag_${type}_${string}.${YYYYMMDDHH}.nc4 pe*.${type}_${loop}.nc4
         gzip diag_${type}_${string}.${YYYYMMDDHH}.nc4*
         echo "diag_${type}_${string}.${YYYYMMDDHH}.nc4*" >> listrad
         numfile_rad=`expr ${numfile_rad} + 1`
      else
         echo 'No diag_' ${type} 'exist'
      fi
   done
fi

done

if [ ${gsi_type} == "OBSERVER" ]; then
  cp_vrfy *diag*ges* ${observer_nwges_dir}/.
  if [ ${mem_type} == "MEAN" ]; then
  mkdir_vrfy -p ${observer_nwges_dir}/../../../observer_diag/${YYYYMMDDHH}/ensmean/observer_gsi
  cp_vrfy *diag*ges* ${observer_nwges_dir}/../../../observer_diag/${YYYYMMDDHH}/ensmean/observer_gsi/.
  else
  mkdir_vrfy -p ${observer_nwges_dir}/../../../observer_diag/${YYYYMMDDHH}/${slash_ensmem_subdir}/observer_gsi
  cp_vrfy *diag*ges* ${observer_nwges_dir}/../../../observer_diag/${YYYYMMDDHH}/${slash_ensmem_subdir}/observer_gsi/.
  fi
fi

#
#-----------------------------------------------------------------------
#
# cycling radiance bias corretion files
#
#-----------------------------------------------------------------------

if [ ${DO_RADDA} == "TRUE" ]; then
  if [ ${cycle_type} == "spinup" ]; then
    spinup_or_prod_rrfs=spinup
  else
    spinup_or_prod_rrfs=prod
  fi
  if [ ${numfile_cnv} -gt 0 ]; then
     tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat_nc `cat listcnv`
     cp_vrfy ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat_nc  ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_cnvstat
  fi
  if [ ${numfile_rad} -gt 0 ]; then
     tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat_nc `cat listrad`
     cp_vrfy ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat_nc  ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat
  fi
  if [ ${numfile_rad_bin} -gt 0 ]; then
     tar -cvzf rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat `cat listrad_bin`
     cp_vrfy ./rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat  ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_radstat
  fi

  cp_vrfy ./satbias_out ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias
  cp_vrfy ./satbias_pc.out ${satbias_dir}/rrfs.${spinup_or_prod_rrfs}.${YYYYMMDDHH}_satbias_pc
fi

#
#-----------------------------------------------------------------------
#
# adjust soil T/Q based on analysis increment
#
#-----------------------------------------------------------------------
#
if [ ${BKTYPE} -eq 0 ] && [ ${ob_type} == "conv" -o ${ob_type} == "all" ] && [ "${DO_SOIL_ADJUST}" = "TRUE" ]; then  # warm start
  cd ${bkpath}
  if [ "${IO_LAYOUT_Y_IN}" == "1" ]; then
    ln_vrfy -snf ${fixgriddir}/fv3_grid_spec                fv3_grid_spec
  else
    for ii in ${list_iolayout}
    do
      iii=`printf %4.4i $ii`
      ln_vrfy  -snf ${gridspec_dir}/fv3_grid_spec.${iii}    fv3_grid_spec.${iii}
    done
  fi

cat << EOF > namelist.soiltq
 &setup
  fv3_io_layout_y=${IO_LAYOUT_Y_IN},
  iyear=${YYYY},
  imonth=${MM},
  iday=${DD},
  ihour=${HH},
  iminute=0,
 /
EOF

  adjustsoil_exec="${EXECDIR}/adjust_soiltq.exe"

  if [ -f $adjustsoil_exec ]; then
    print_info_msg "$VERBOSE" "
Copying the adjust soil executable to the run directory..."
    cp_vrfy ${adjustsoil_exec} adjust_soiltq.exe
  else
    print_err_msg_exit "\
The adjust_soiltq.exe specified in ${EXECDIR} does not exist.
Build adjust_soiltq.exe and rerun."
  fi

  $APRUN ./adjust_soiltq.exe || print_err_msg_exit "\
  Call to executable to run adjust soil returned with nonzero exit code."

fi

#
#-----------------------------------------------------------------------
#
# update boundary condition absed on analysis results.
# This will generate a new boundary file at 0-hour
#
#-----------------------------------------------------------------------
#
if [ ${BKTYPE} -eq 0 ] && [ "${DO_UPDATE_BC}" = "TRUE" ]; then  # warm start
  cd ${bkpath}

cat << EOF > namelist.updatebc
 &setup
  fv3_io_layout_y=${IO_LAYOUT_Y_IN},
  bdy_update_type=1,
  grid_type_fv3_regional=2,
 /
EOF

  update_bc_exec="${EXECDIR}/update_bc.exe"
  cp gfs_bndy.tile7.000.nc gfs_bndy.tile7.000.nc_before_update

  if [ -f $update_bc_exec ]; then
    print_info_msg "$VERBOSE" "
Copying the update bc executable to the run directory..."
    cp_vrfy ${update_bc_exec} update_bc.exe 
  else
    print_err_msg_exit "\
The update_bc.exe specified in ${EXECDIR} does not exist.
Build update_bc.exe and rerun."
  fi

  $APRUN ./update_bc.exe || print_err_msg_exit "\
  Call to executable to run update bc returned with nonzero exit code."

fi

#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
ANALYSIS GSI completed successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

