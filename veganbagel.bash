#!/usr/bin/env bash
#
# This script takes an directory with DICOM files of a structural 3D T1w MR brain scan as input
# and then generates a map of regional volume changes in relation to an age- and sex-matched
# cohort of pre-processed normal scans.
#
# Estimating regional deviations of brain volume from a patient’s normative age cohort is
# challenging and entails immense inter-reader variation. We propose an automated workflow for
# sex- and age-dependent estimation of brain volume changes relative to a normative population.
#
# Essentially, sex- and age-dependent gray-matter (GM) templates based on T1w MRIs of healthy
# subjects were used to generate voxel-wise mean and standard deviation template maps with the
# respective age +/-2 using CAT12 for SPM12. These templates can then be used to generate
# atrophy maps for out-of-sample subjects.
#
# The colour-coded volume maps can be automatically exported back to the PACS.
#
# Please run ./veganbagel.bash -h for usage information.
# See setup.veganbagel.bash (and also setup.brainstem.bash) for configuration options.
# Check README for requirements.
#
# Authors:
# - Julian Caspers <julian.caspers@med.uni-duesseldorf.de>
# - Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>
#


### Acknowledgements
##############################################################################
#
# This script is based on a template by BASH3 Boilerplate v2.3.0
# http://bash3boilerplate.sh/#authors
#
# The BASH3 Boilerplate is under the MIT License (MIT) and is
# Copyright (c) 2013 Kevin van Zonneveld and contributors


### Command line options
##############################################################################

# shellcheck disable=SC2034
read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -i --input [arg]    Directory containing the DICOM input files. Required.
  -k --keep-workdir   After running, copy the temporary work directory into the input directory.
  -c --cleanup        After running, empty the source directory (reference DICOM and translation matrices are kept)
  -p --no-pacs        Do not send the results to the PACS.
  -v                  Enable verbose mode, print script as it is executed.
  -d --debug          Enables debug mode.
  -h --help           This page.
EOF

# shellcheck disable=SC2034
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 This scripts takes a directory with DICOM files of a 3D T1w structural MRI brain
 scan and generates a map of regional volume changes in relation to an age- and
 sex-matched cohort of pre-processed normal scans.
EOF

# shellcheck source=b3bp.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tools/b3bp.bash"

# Set version
version_veganbagel=$(cd "${__dir}" && git describe --always)

# Set UID prefix
prefixUID=12

### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit {
  # Delete the temporary workdir, if necessary
  if [[ ! "${arg_k:?}" = "1" ]] && [[ "${workdir:-}" ]]; then
    rm -rf "${workdir}"
    info "Removed temporary workdir"
  fi
}
trap __b3bp_cleanup_before_exit EXIT

# requires `set -o errtrace`
function __b3bp_err_report {
    local error_code
    error_code=${?}
    # shellcheck disable=SC2154
    error "Error in ${__file} in function ${1} on line ${2}"
    exit ${error_code}
}

# Uncomment the following line for always providing an error backtrace
# trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR


### Command-line argument switches
##############################################################################

# debug mode
if [[ "${arg_d:?}" = "1" ]]; then
  set -o xtrace
  LOG_LEVEL="4"
  # Enable error backtracing
  trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
fi

# verbose mode
if [[ "${arg_v:?}" = "1" ]]; then
  set -o verbose
fi

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
  # Help exists with code 1
  help "Help using ${0}"
fi


### Validation. Error out if the things required for your script are not present
##############################################################################

[[ "${arg_i:-}" ]]     || help  "Setting a directory with -i or --input is required"
[[ "${LOG_LEVEL:-}" ]] || error "Cannot continue without LOG_LEVEL."

# Check for setup.veganbagel.bash, then source it
if [[ ! -f "${__dir}/setup.veganbagel.bash" ]]; then
  error "\"${__dir}/setup.veganbagel.bash\" does not exist."
else
  # shellcheck source=setup.veganbagel.bash
  source "${__dir}/setup.veganbagel.bash"
  export LANG=${language_encoding}
fi

# Check if the input/source directory exists
if [[ ! -d "${arg_i}" ]]; then
  error "\"${arg_i}\" is not a directory or does not exist."
fi 

# Get absolute path of the input directory (just in case) and exit if directory is empty
source_dir=$(realpath "${arg_i}")
if [[ "x"$(ls -1A "${source_dir}") = "x" ]]; then
  error "Directory \"${source_dir}\" is empty."
fi 

### Source the necessary functions
##############################################################################

# shellcheck source=../brainstem/tools/bash/getDCMTag.bash
source "${__dir}/../../tools/bash/getDCMTag.bash"
# shellcheck source=../brainstem/tools/bash/convertNII2TIFF.bash
source "${__dir}/../../tools/bash/convertNII2TIFF.bash"
# shellcheck source=../brainstem/tools/convertIMG2DCM.bash
source "${__dir}/../../tools/bash/convertIMG2DCM.bash"
# shellcheck source=../brainstem/tools/bash/convertDCM2NII.bash
source "${__dir}/../../tools/bash/convertDCM2NII.bash"
# shellcheck source=../brainstem/tools/bash/sendDCM.bash
source "${__dir}/../../tools/bash/sendDCM.bash"

# shellcheck source=bash/tools/estimateVolumechanges.bash
source "${__dir}/tools/bash/estimateVolumechanges.bash"
# shellcheck source=bash/tools/convertNII2TIFF_matlab.bash
source "${__dir}/tools/bash/convertNII2TIFF_matlab.bash"
# shellcheck source=bash/tools/colourLUT.bash
source "${__dir}/tools/bash/colourLUT.bash"

### Runtime
##############################################################################

info "Starting volumetric estimation of gross atrophy and brain age longitudinally (veganbagel):"
info "  version: ${version_veganbagel}"
info "  source_dir: ${source_dir}"

# Create the temporary workdir
workdir=$(TMPDIR="${tmpdir}" mktemp --directory -t "${__base}-XXXXXX")
info "  workdir: ${workdir}"

# Copy all DICOM files, except for files which are of the modality presentation
# state (PR) or a residual ref_dcm.dcm, into the workdir and create an index file
mkdir "${workdir}/dcm-in"
${dcmftest} "${source_dir}/"* | \
  grep -E "^yes:" | \
  grep -vE "^yes: .*\/ref_dcm.dcm$" | \
  while read bool dcm; do
    modality=$(getDCMTag "${dcm}" "0008,0060" "n")
    if [[ $modality != "PR" ]]; then
      cp "${dcm}" "${workdir}/dcm-in"
      echo $(LANG=C printf "%03d" $(getDCMTag "${dcm}" "0020,0013" "n")) $dcm >> "${workdir}/index-dcm-in"
    fi
  done || true
set -u modality

# Get the middle line (minus two) of the index-dcm-in file as the reference DICOM file
# The reference DICOM file will be used as a source for DICOM tags, when (at the end)
# a DICOM dataset is created to send it back to the PACS. Since reference scans might
# be embedded inside the DICOM stack at the beginning, end, or in the middle, we
# choose a DICOM file two off the center. This should yield a reasonable window/center
# setting in case of MR examinations, as well.
dcm_index_lines=$(wc -l "${workdir}/index-dcm-in" | cut -d" " -f1)
dcm_index_lines_middle=$(echo "($dcm_index_lines / 2) - 2" | bc)
ref_dcm=$(sed -n "${dcm_index_lines_middle},${dcm_index_lines_middle}p" "${workdir}/index-dcm-in" | cut -d" " -f2)
info "  ref_dcm: ${ref_dcm}"

# Get and save the subject's name (for debugging reasons)
getDCMTag "${ref_dcm}" "0010,0010" > "${workdir}/name"

# Check the modality, we need a MR scan
if [[ $(getDCMTag "${ref_dcm}" "0008,0060") != "MR" ]]; then
  error "\"${ref_dcm}\" is not a MR."
fi

# Check if contrast was applied, we need an unenhanced MR
contrastApplied=$(getDCMTag "${ref_dcm}" "0018,0010")
if [[ ! "$contrastApplied" = "NOT_FOUND_IN_DICOM_HEADER" ]]; then
  error "    Only non-enhanced scans are supported."
fi

# Get and age and sex of the subject
age=$(getDCMTag "${ref_dcm}" "0010,1010" | sed -e 's/0\+//' -e 's/Y$//')
sex=$(getDCMTag "${ref_dcm}" "0010,0040")
echo $age > "${workdir}/age"
echo $sex > "${workdir}/sex"

# Check if the appropriate mean and standard deviation (std) templates are available
if [[ ! -f "${template_volumes}/${age}${sex}smwp1_mean.nii" ]]; then
  error "There is no mean template available for ${age}/${sex} in ${template_volumes}."
fi
if [[ ! -f "${template_volumes}/${age}${sex}smwp1_std.nii" ]]; then
  error "There is no standard deviation template available for ${age}/${sex} in ${template_volumes}."
fi

info "  mean template: ${template_volumes}/${age}${sex}smwp1_mean.nii"
info "  standard deviation template: ${template_volumes}/${age}${sex}smwp1_std.nii"

### Step 1: Create NII of original DCM files
mkdir "${workdir}/nii-in"
# convertDCM2NII exports the variable nii, which contains the full path to the converted NII file
# The third parameter to convertDCM2NII intentionally disables the creation of a gzip'ed NII
convertDCM2NII "${workdir}/dcm-in/" "${workdir}/nii-in" "n" || error "convertDCM2NII failed"

### Step 2: Create TIFF of NII
mkdir "${workdir}/nii-in-tiff"
convertNII2TIFF "${nii}" "${workdir}/nii-in-tiff" || error "convertNII2TIFF failed"

### Step 3: Estimate regional volume
# estimateVolumechanges export the variable zmap, which is the full path to the zmap
estimateVolumechanges "${nii}" "${template_volumes}" "${age}" "${sex}" || error "estimateVolumechanges failed"

### Step 4: Convert resulting zmap to TIFF (grayscale)
mkdir "${workdir}/tiff-in-zmap"
convertNII2TIFF_matlab "${zmap}" "${workdir}/tiff-in-zmap"

### Step 5: Generate and apply colour lookup tables to the zmap, then merge with the original scan
mkdir "${workdir}/out"
colourLUT "${workdir}/nii-in-tiff" "${workdir}/tiff-in-zmap" "${workdir}/out" "${ref_dcm}"

### Step 6: Convert merged images to DICOM
mkdir "${workdir}/dcm-out"
# Get the series number from the reference DICOM and add $base_series_no from setup.veganbagel.bash
ref_series_no=$(getDCMTag "${ref_dcm}" "0020,0011")
series_no=$(echo "${base_series_no} + ${ref_series_no}" | bc)
series_description=$(echo $(getDCMTag "${ref_dcm}" "0008,103e" "n") Volume Map)
convertIMG2DCM "${workdir}/out/jpg" "${workdir}/dcm-out" ${series_no} "${series_description}" "${ref_dcm}" || error "convertIMG2DCM failed"

### Step 7: Modify some more DICOM tags specific to veganbagel

# Set some version information on this tool
"${dcmodify}" \
  --no-backup \
  --insert "(0008,1090)"="BrainImAccs veganbagel - Research" \
  --insert "(0018,1020)"="BrainImAccs veganbagel ${version_veganbagel}" \
  "${workdir}/dcm-out"/*.dcm

info "Modified DICOM tags specific to $(basename ${0})"

### Step 8: Send DCM to PACS
if [[ ! "${arg_p:?}" = "1" ]]; then
  sendDCM "${workdir}/dcm-out/" "jpeg8" || error "sendDCM failed"
fi

### Step 9: Cleaning up
# Copy reference DICOM file to ref_dcm.dcm and copy translation matrices to the source dir
info "Copying reference DICOM file and translation matrices to source dir"
cp "${ref_dcm}" "${source_dir}/ref_dcm.dcm"

# Remove the DICOM files from the source directory, but keep ref_dcm.dcm, translation matrices and log (if it exists)
if [[ "${arg_c:?}" = "1" ]]; then
  if [ -e "${source_dir}/log" ]; then
    info "Removing everything except reference DICOM, translation matrices and log from the source dir"
  else
    info "Removing everything except reference DICOM and translation matrices from the source dir"
  fi
  find "${source_dir}" -type f -not -name 'ref_dcm.dcm' -not -name '*.mat' -not -name 'log' -delete
fi

# Keep or discard the workdir. The exit trap (see __b3bp_cleanup_before_exit) is used to discard the temporary workdir.
if [[ "${arg_k:?}" = "1" ]]; then
  kept_workdir="${source_dir}/$(basename ${BASH_SOURCE[0]})-workdir-$(date -u +'%Y%m%d-%H%M%S-UTC')"
  mv "${workdir}" "${kept_workdir}"
  info "Keeping temporary workdir as ${kept_workdir}"
fi
