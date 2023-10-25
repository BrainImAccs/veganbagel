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
  -a --age [arg]      Optional and not recommended. Overrides the subject's age as extracted from the DICOMs.
  -s --sex [arg]      Optional and not recommended. Overrides the subject's sex as extracted from the DICOMs.
  -k --keep-workdir   After running, copy the temporary work directory into the input directory.
  -c --cleanup        After running, empty the source directory (reference DICOM, translation matrices and logs are kept)
  -t --total-cleanup  After running, delete the source directory
  -n --no-pacs        Do not send the results to the PACS.
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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/BrainSTEM/tools/b3bp.bash"

# Set version
if [[ -e "${__dir}/version" ]]; then
  version_veganbagel=$(cat "${__dir}/version")
else
  version_veganbagel=$(cd "${__dir}" && git describe --always)
fi

# Set UID prefix
prefixUID=12

### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit {
  # Delete the temporary workdir, if necessary
  if { [[ ! "${arg_k:?}" = "1" ]] || [[ "${arg_t:?}" = "1" ]]; } && [[ "${workdir:-}" ]]; then
    rm -rf "${workdir}"
    info "Removed temporary workdir ${workdir}"
  fi
  # Delete the source dir, if necessary
  if [[ "${arg_t:?}" = "1" ]] && [[ "${source_dir:-}" ]]; then
    rm -rf "${source_dir}"
    info "Removed source dir ${source_dir}"
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
source "${__dir}/BrainSTEM/tools/bash/getDCMTag.bash"
# shellcheck source=../brainstem/tools/convertIMG2DCM.bash
source "${__dir}/BrainSTEM/tools/bash/convertIMG2DCM.bash"
# shellcheck source=../brainstem/tools/bash/convertDCM2NII.bash
source "${__dir}/BrainSTEM/tools/bash/convertDCM2NII.bash"
# shellcheck source=../brainstem/tools/bash/sendDCM.bash
source "${__dir}/BrainSTEM/tools/bash/sendDCM.bash"

# shellcheck source=bash/tools/estimateVolumechanges.bash
source "${__dir}/tools/bash/estimateVolumechanges.bash"
# shellcheck source=bash/tools/colourLUT.bash
source "${__dir}/tools/bash/colourLUT.bash"
# shellcheck source=bash/tools/qcOverlay.bash
source "${__dir}/tools/bash/qcOverlay.bash"
# shellcheck source=bash/tools/calculateBrainAGE.bash
source "${__dir}/tools/bash/calculateBrainAGE.bash"

### Runtime
##############################################################################

info "Starting volumetric estimation of gross atrophy and brain age longitudinally (veganbagel):"
info "  version: ${version_veganbagel}"
info "  source_dir: ${source_dir}"

# Create the temporary workdir
workdir=$(TMPDIR="${tmpdir}" mktemp --directory -t "${__base}-XXXXXX")
info "  workdir: ${workdir}"

# Copy all DICOM files, except for files which are of the modality presentation
# state (PR) or a residual ref_dcm.dcm, into the workdir and create an index file,
# which contains the ImagePositionPatient DICOM tag (for sorting) and the DICOM file
mkdir "${workdir}/dcm-in"
${dcmftest} "${source_dir}/"* | \
  grep -E "^yes:" | \
  grep -vE "^yes: .*\/ref_dcm.dcm$" | \
  while read bool dcm; do
    modality=$(getDCMTag "${dcm}" "0008,0060" "n")
    if [[ $modality != "PR" ]]; then
      cp "${dcm}" "${workdir}/dcm-in"
      instanceNo=$(LANG=C printf "%03d" $(getDCMTag "${dcm}" "0020,0013" "n"))
      imagePosPatient=$(getDCMTag "${dcm}" "0020,0032" "n")
      echo ${instanceNo}\\"${imagePosPatient}" $dcm >> "${workdir}/index-dcm-in-unsorted"
      # Please ignore the following ", it just fixes vim syntax highlighting after aboves escape
    fi
  done || true
set -u modality
set -u imagePosPatient

# The ImagePositionPatient tag contains information on the x, y and z position in mm of the
# upper left voxel of the image. We sort by the z (axial), then x (sagittal), then y (coronal)
# position to later extract the reference DICOM from the middle of the stack (see below) and
# for properly merging colour maps with the original DICOMs
sort -n -k4,4 -k2,2 -k3,3 -t'\' "${workdir}/index-dcm-in-unsorted" | sed -e 's/\\/ /' > "${workdir}/index-dcm-in"

# Get the middle line (minus two) of the index-dcm-in file as the reference DICOM file
# The reference DICOM file will be used as a source for DICOM tags, when (at the end)
# a DICOM dataset is created to send it back to the PACS. This should yield a reasonable
# window width/center setting in case of MR examinations, as well.
dcm_index_lines=$(wc -l "${workdir}/index-dcm-in" | cut -d" " -f1)
dcm_index_lines_middle=$(echo "($dcm_index_lines / 2) - 2" | bc)
ref_dcm=$(sed -n "${dcm_index_lines_middle},${dcm_index_lines_middle}p" "${workdir}/index-dcm-in" | cut -d" " -f3)
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
patientBirthDate=$(getDCMTag "${ref_dcm}" "PatientBirthDate")
studyDate=$(getDCMTag "${ref_dcm}" "StudyDate")

if [[ "${patientBirthDate}" =~ ^[0-9]{8}$ && "${studyDate}" =~ ^[0-9]{8}$ ]]; then
  age_days=$(dateutils.ddiff --input-format="%Y%m%d" --format="%d" "${patientBirthDate}" "${studyDate}")
  age_years_dec=$(echo "${age_days} / 365.25" | bc -l)
fi

age=$(getDCMTag "${ref_dcm}" "0010,1010" | sed -e 's/0\+//' -e 's/Y$//')
if [[ "${arg_a:-}" ]]; then
  if [[ ! "${arg_a}" =~ ^[0-9.]+$ ]]; then
    error "Subject's age has to be an integer."
  else
    warning "Overriding the age found in the DICOM (${age}) and using the supplied ${arg_a}."
    age=$(echo ${arg_a} | cut -d'.' -f2)
    age_years_dec=${arg_a}
  fi
fi
echo ${age} > "${workdir}/age"
echo ${age_days} > "${workdir}/age_days"
echo ${age_years_dec} > "${workdir}/age_years_dec"

sex=$(getDCMTag "${ref_dcm}" "0010,0040")
if [[ "${arg_s:-}" ]]; then
  if [[ ! "${arg_s}" =~ ^(M|F)$ ]]; then
    error "Subject's sex has to be either F or M."
  else
    warning "Overriding the sex found in the DICOM (${sex}) and using the supplied ${arg_s}."
    sex=${arg_s}
  fi
fi
echo $sex > "${workdir}/sex"

# Check if the appropriate mean and standard deviation (std) templates are available
if [[ ! -f "${template_volumes}/${age}${sex}smwp1_mean.nii.gz" ]]; then
  error "There is no mean template available for ${age}/${sex} in ${template_volumes}."
fi
if [[ ! -f "${template_volumes}/${age}${sex}smwp1_std.nii.gz" ]]; then
  error "There is no standard deviation template available for ${age}/${sex} in ${template_volumes}."
fi

info "  mean template: ${template_volumes}/${age}${sex}smwp1_mean.nii.gz"
info "  standard deviation template: ${template_volumes}/${age}${sex}smwp1_std.nii.gz"

### Create NII of original DCM files
mkdir "${workdir}/nii-in"
# convertDCM2NII exports the variable nii, which contains the full path to the converted NII file
# The third parameter to convertDCM2NII intentionally disables the creation of a gzip'ed NII
convertDCM2NII "${workdir}/dcm-in/" "${workdir}/nii-in" "n" || error "convertDCM2NII failed"

### Estimate regional volume
# estimateVolumechanges exports
#  * the variable processed_nii, which is the full path to the result of the standalone CAT12 segmentation
#  * the variable zmap, which is the full path to the zmap
estimateVolumechanges "${nii}" "${template_volumes}" "${age}" "${sex}" || error "estimateVolumechanges failed"

## ColourLUT

### Calculate the Brain Age Gap Estimation (BrainAGE)
# calculateBrainAGE exports
#  * the variable brainage_estimation, which is the output of the model, i.e. the estimated age of the brain
#  * the variable BrainAGE, which is the Brain Age Gap Estimation (brainage_estimation - age_years_dec)
mkdir "${workdir}/brainage_estimation"
calculateBrainAGE "${processed_nii}" "${workdir}/brainage_estimation" "${age_years_dec}" || error "calculateBrainAGE failed"

### Generate and apply colour lookup tables to the zmap, then merge with the original scan
mkdir "${workdir}/cmap-out"
colourLUT "${nii}" "${zmap}" "${workdir}/cmap-out" "${ref_dcm}" "${age_years_dec}" "${brainage_estimation}"

### Generate and apply colour lookup tables to the zmap, then merge with the original scan
mkdir "${workdir}/qc-out"
qc=$(dirname "${zmap}")/p0$(basename "${nii}")
qcOverlay "${nii}" "${qc}" "${workdir}/qc-out" "${ref_dcm}"

# Get the series number and description from the reference DICOM
ref_series_no=$(getDCMTag "${ref_dcm}" "0020,0011" "n")
ref_series_description=$(getDCMTag "${ref_dcm}" "0008,103e" "n")

# Convert colour map and QC images to DICOM and export to PACS
for type in cmap qc; do
  echo
  info "Processing ${type}"

  ### Convert merged images to DICOM
  mkdir "${workdir}/${type}-dcm-out"

  # Define series number and description
  if [[ "${type}" = "cmap" ]]; then
    series_no=$(echo "${base_series_no} + ${ref_series_no}" | bc)
    series_description="${ref_series_description} Volume Map"
  elif [[ "${type}" = "qc" ]]; then
    series_no=$(echo "${base_series_no} + ${ref_series_no}" | bc)
    series_description="${ref_series_description} QC: Segmentation"
  fi

  # Convert previously generated images to DICOM
  convertIMG2DCM "${workdir}/${type}-out" "${workdir}/${type}-dcm-out" ${series_no} "${series_description}" "${ref_dcm}" || error "convertIMG2DCM failed"

  ### Modify some more DICOM tags specific to veganbagel

  # Set some version information on this tool
  "${dcmodify}" \
    --no-backup \
    --insert "(0008,1090)"="BrainImAccs veganbagel - Research" \
    --insert "(0018,1020)"="BrainImAccs veganbagel ${version_veganbagel}" \
    "${workdir}/${type}-dcm-out"/*.dcm

  info "  Modified DICOM tags specific to $(basename ${0})"

  ### Send DCM to PACS
  if [[ ! "${arg_n:?}" = "1" ]]; then
    sendDCM "${workdir}/${type}-dcm-out/" "jpeg8" || error "sendDCM failed"
  fi
done

### Cleaning up
# Copy reference DICOM file to ref_dcm.dcm and copy translation matrices to the source dir
info "Copying reference DICOM file and translation matrices to source dir"
cp "${ref_dcm}" "${source_dir}/ref_dcm.dcm"

# Remove the DICOM files from the source directory, but keep ref_dcm.dcm, translation matrices and log (if it exists)
if [[ "${arg_c:?}" = "1" ]]; then
  if [ -e "${source_dir}/log" ]; then
    info "Removing everything except reference DICOM and log from the source dir. Keeping CAT12 reports."
  else
    info "Removing everything except reference DICOM from the source dir. Keeping CAT12 reports."
  fi
  find "${source_dir}" -type f -not -name 'ref_dcm.dcm' -not -name '*.mat' -not -name 'log' -delete
  cp -a "${workdir}/nii-in/report" "${source_dir}"
fi

# Keep or discard the workdir. The exit trap (see __b3bp_cleanup_before_exit) is used to discard the temporary workdir.
if [[ "${arg_k:?}" = "1" ]]; then
  kept_workdir="${source_dir}/$(basename ${BASH_SOURCE[0]})-workdir-$(date -u +'%Y%m%d-%H%M%S-UTC')"
  mv "${workdir}" "${kept_workdir}"
  info "Keeping temporary workdir as ${kept_workdir}"
fi
