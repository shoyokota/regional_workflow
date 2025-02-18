#
# TEST PURPOSE/DESCRIPTION:
# ------------------------
#
# This test checks the capability of the workflow to have the user 
# specify a new grid (as opposed to one of the predefined ones in the 
# workflow) of GFDLgrid type.  Note that this test sets the workflow 
# variable 
#
#   GFDLgrid_USE_GFDLgrid_RES_IN_FILENAMES 
#
# to "TRUE" (which is its default value); see the UFS SRW User's Guide 
# for a description of this variable. 
#

RUN_ENVIR="community"
PREEXISTING_DIR_METHOD="rename"

CCPP_PHYS_SUITE="FV3_GFS_2017_gfdlmp"

EXTRN_MDL_NAME_ICS="FV3GFS"
EXTRN_MDL_NAME_LBCS="FV3GFS"
USE_USER_STAGED_EXTRN_FILES="TRUE"

DATE_FIRST_CYCL="20190701"
DATE_LAST_CYCL="20190701"
CYCL_HRS=( "00" )

FCST_LEN_HRS="6"
LBC_SPEC_INTVL_HRS="3"
#
# Define custom grid.
#
GRID_GEN_METHOD="GFDLgrid"

GFDLgrid_LON_T6_CTR="-97.5"
GFDLgrid_LAT_T6_CTR="38.5"
GFDLgrid_STRETCH_FAC="1.5"
GFDLgrid_RES="96"
GFDLgrid_REFINE_RATIO="2"
  
#num_margin_cells_T6_left="9"
#GFDLgrid_ISTART_OF_RGNL_DOM_ON_T6G=$(( num_margin_cells_T6_left + 1 ))
GFDLgrid_ISTART_OF_RGNL_DOM_ON_T6G="10"

#num_margin_cells_T6_right="9"
#GFDLgrid_IEND_OF_RGNL_DOM_ON_T6G=$(( GFDLgrid_RES - num_margin_cells_T6_right ))
GFDLgrid_IEND_OF_RGNL_DOM_ON_T6G="87"

#num_margin_cells_T6_bottom="9"
#GFDLgrid_JSTART_OF_RGNL_DOM_ON_T6G=$(( num_margin_cells_T6_bottom + 1 ))
GFDLgrid_JSTART_OF_RGNL_DOM_ON_T6G="10"

#num_margin_cells_T6_top="9"
#GFDLgrid_JEND_OF_RGNL_DOM_ON_T6G=$(( GFDLgrid_RES - num_margin_cells_T6_top ))
GFDLgrid_JEND_OF_RGNL_DOM_ON_T6G="87"

GFDLgrid_USE_GFDLgrid_RES_IN_FILENAMES="TRUE"

DT_ATMOS="100"

LAYOUT_X="6"
LAYOUT_Y="6"
BLOCKSIZE="26"

POST_OUTPUT_DOMAIN_NAME="custom_GFDLgrid"

QUILTING="TRUE"
if [ "$QUILTING" = "TRUE" ]; then
  WRTCMP_write_groups="1"
  WRTCMP_write_tasks_per_group=$(( 1*LAYOUT_Y ))
  WRTCMP_output_grid="rotated_latlon"
  WRTCMP_cen_lon="${GFDLgrid_LON_T6_CTR}"
  WRTCMP_cen_lat="${GFDLgrid_LAT_T6_CTR}"
# The following have not been tested...
  WRTCMP_lon_lwr_left="-25.0"
  WRTCMP_lat_lwr_left="-15.0"
  WRTCMP_lon_upr_rght="25.0"
  WRTCMP_lat_upr_rght="15.0"
  WRTCMP_dlon="0.24"
  WRTCMP_dlat="0.24"
fi
