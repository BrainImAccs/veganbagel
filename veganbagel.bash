#!/usr/bin/env bash
#
# This script takes an directory with DICOM files or a single NIfTI file of a structural 3D
# T1w MR brain scan as input and then generates a map of regional volume changes in relation
# to an age- and sex-matched cohort of pre-processed normal scans.
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
#
# See setup.veganbagel.bash (and also setup.brainstem.bash) for configuration options.
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
  -i --input [arg]          Either directory containing the DICOM input files or a NIfTI file. Required.
  -a --age [arg]            Optional for a DICOM dir. Overrides age as extracted from the DICOMs. --date-of-birth or this required for NIfTI files. Decimal format (42.1234) recommended for BrainAGE.
  -b --date-of-birth [arg]  Optional for a DICOM dir. Overrides date of birth as extracted from the DICOMs. --age or this required for NIfTI files. Format: YYYYMMDD.
  -e --study-date [arg]     Optional for a DICOM dir. Overrides study date as extracted from the DICOMs. Required for NIfTI files. Format: YYYYMMDD.
  -s --sex [arg]            Optional for a DICOM dir. Overrides sex as extracted from the DICOMs. Required for NIfTI files.
  -k --keep-workdir         After running, copy the temporary work directory into the input directory.
  -c --cleanup              After running, empty the source directory (reference DICOM, translation matrices and logs are kept). Will only work for DICOM directories.
  -t --total-cleanup        After running, delete the source directory. Will only work for DICOM directories.
  -n --no-pacs              Do not send the results to the PACS. Default when a NIfTI file is used as input.
  -v                        Enable verbose mode, print script as it is executed.
  -d --debug                Enables debug mode.
  -h --help                 This.
EOF

# shellcheck disable=SC2034
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 This scripts takes a directory with DICOM files or a single NIfTI file of a 3D
 T1w structural MRI brain scan and generates a map of regional volume changes
 in relation to an age- and sex-matched cohort of pre-processed normal scans.
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
  if { [[ ! "${arg_k:?}" = "1" ]] || [[ "${arg_t:?}" = "1" ]]; } && [[ "x${workdir:-}" != "x" ]] && [[ -d "${workdir}" ]]; then
    rm -rf "${workdir}"
    info "Removed temporary workdir ${workdir}"
  fi

  # If --total-cleanup was defined (and a DICOM dir was supplied) delete the source dir
  if [[ "${arg_t:?}" = "1" && "${source:-}" ]]; then
    if [[ "${dicom:-}" = "true" ]]; then
      rm -rf "${source}"
      info "Removed source dir ${source}"
    else
      warning "--total-cleanup was set, but a NIfTI file was supplied. Source directory will not be deleted."
    fi
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

[[ "${arg_i:-}" ]]     || help  "Setting a DICOM directory or NIfTI file with -i or --input is required."
[[ "${LOG_LEVEL:-}" ]] || error "Cannot continue without LOG_LEVEL."

# Check for setup.veganbagel.bash, then source it
if [[ ! -f "${__dir}/setup.veganbagel.bash" ]]; then
  error "\"${__dir}/setup.veganbagel.bash\" does not exist."
else
  # shellcheck source=setup.veganbagel.bash
  source "${__dir}/setup.veganbagel.bash"
fi

# Check if the input/source directory or file exists
if [[ ! -e "${arg_i}" ]]; then
  error "\"${arg_i}\" does not exist."
fi

# Get absolute path of the input directory (just in case) and exit if directory is empty
source=$(realpath "${arg_i}")

# Check if it is a directory (we then assume it is a DICOM directory and not a NIfTI file)
if [[ -d "${source}" ]]; then
  dicom=true
  # Check if directory is empty
  if [[ "x"$(ls -1A "${source}") = "x" ]]; then
    error "Directory \"${source}\" is empty."
  fi 
# Check if it is a file with a .nii or .nii.gz extension
elif [[ -f "${source}" && "${source}" =~ \.(nii|nii\.gz)$ ]]; then
  dicom=false
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
info "  source: ${source}"
info "  dicom: ${dicom}"

# Create the temporary workdir
workdir=$(TMPDIR="${tmpdir}" mktemp --directory -t "${__base}-XXXXXX")
info "  workdir: ${workdir}"

# Preparations and checks when a DICOM directory was supplied
if [[ "${dicom:-}" = "true" ]]; then
  # Copy all DICOM files, except for files which are of the modality presentation
  # state (PR) or a residual ref_dcm.dcm, into the workdir and create an index file,
  # which contains the ImagePositionPatient DICOM tag (for sorting) and the DICOM file
  mkdir "${workdir}/dcm-in"
  ${dcmftest} "${source}/"* | \
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
  age=$(getDCMTag "${ref_dcm}" "0010,1010" | sed -e 's/0\+//' -e 's/Y$//')
  sex=$(getDCMTag "${ref_dcm}" "0010,0040")

  # Get birth date and study date
  patientBirthDate=$(getDCMTag "${ref_dcm}" "PatientBirthDate")
  studyDate=$(getDCMTag "${ref_dcm}" "StudyDate")
fi

# Check if age was overriden on the command line
if [[ "${arg_a:-}" ]]; then
  if [[ ! "${arg_a}" =~ ^[0-9.]+$ ]]; then
    error "Subject's age has to be an integer."
  else
    if [[ "${dicom:-}" = "true" ]]; then
      warning "Overriding the age found in the DICOM (${age}) and using the supplied ${arg_a}."
    fi

    age=$(echo ${arg_a} | cut -d'.' -f1)
    age_years_dec=${arg_a}
  fi
fi

# Check if date of birth was overriden on the command line
if [[ "${arg_b:-}" ]]; then
  if [[ ! "${arg_b}" =~ ^[0-9]{8}$ ]]; then
    error "--date-of-birth must be in the format YYYYMMDD."
  else
    if [[ "${dicom:-}" = "true" ]]; then
      warning "Overriding the date of birth found in the DICOM (${patientBirthDate}) and using the supplied ${arg_b}."
    fi

    patientBirthDate=${arg_b}
  fi
fi

# Check if study date was overriden on the command line
if [[ "${arg_e:-}" ]]; then
  if [[ ! "${arg_e}" =~ ^[0-9]{8}$ ]]; then
    error "--study-date must be in the format YYYYMMDD."
  else
    if [[ "${dicom:-}" = "true" ]]; then
      warning "Overriding the study date found in the DICOM (${studyDate}) and using the supplied ${arg_e}."
    fi

    studyDate=${arg_e}
  fi
fi

# At this point age, or patientBirthDate AND studyDate must be set. Otherwise throw an error.
if [[ "x${age:-}" = "x" && ( "x${patientBirthDate:-}" = "x" || "x${studyDate:-}" = "x" ) ]]; then
  if [[ "${dicom:-}" = "true" ]]; then
    error "Either subject's age or both date of birth and study date must be known, but should have been extracted from the DICOM."
  else
    error "Either subject's age or both date of birth and study date must be supplied on the commandline."
  fi
fi

if [[ "x${patientBirthDate:-}" != "x" && "x${studyDate:-}" != "x" && "${patientBirthDate}" =~ ^[0-9]{8}$ && "${studyDate}" =~ ^[0-9]{8}$ ]]; then
  age_days=$(dateutils.ddiff --input-format="%Y%m%d" --format="%d" "${patientBirthDate}" "${studyDate}")
  age_years_dec_temp=$(echo "${age_days} / 365.25" | bc -l)
  age_years_temp=$(echo ${age_years_dec_temp} | cut -d'.' -f1)

  echo ${age_days} > "${workdir}/age_days"

  # Check if age_years_dec was set already. If so, overwrite it and print an info message.
  if [[ "x${age_years_dec:-}" != "x" ]]; then
    warning "Overriding the age ${age_years_dec} and using the ${age_years_dec_temp} calculated from patient's birth and study date."
  fi

  age_years_dec=${age_years_dec_temp}

  if [[ "x${age:-}" != "x" ]]; then
    warning "Overriding the age ${age} and using the ${age_years_temp} calculated from patient's birth and study date."
  fi

  age=${age_years_temp}
fi

echo ${age} > "${workdir}/age"
echo ${age_years_dec} > "${workdir}/age_years_dec"

if [[ "${arg_s:-}" ]]; then
  if [[ ! "${arg_s}" =~ ^(M|F)$ ]]; then
    error "Subject's sex has to be either F or M."
  else
    if [[ "${dicom:-}" = "true" ]]; then
      warning "Overriding the sex found in the DICOM (${sex}) and using the supplied ${arg_s}."
    fi

    sex=${arg_s}
  fi
fi

if [[ "x${sex:-}" = "x" ]]; then
  if [[ "${dicom:-}" = "true" ]]; then
    error "Subject's sex must be known, but should have been extracted from the DICOM."
  else
    error "Subject's sex must be supplied on the commandline."
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
if [[ "${dicom:-}" = "true" ]]; then
  # convertDCM2NII exports the variable nii, which contains the full path to the converted NII file
  # The third parameter to convertDCM2NII intentionally disables the creation of a gzip'ed NII
  convertDCM2NII "${workdir}/dcm-in/" "${workdir}/nii-in" "n" || error "convertDCM2NII failed"
else
  # If a NIfTI file was supplied, copy it to the workdir - Decompress it, if necessary
  if [[ "${source}" =~ \.gz$ ]]; then
    gunzip -c "${source}" > "${workdir}/nii-in/$(basename "${source}" .gz)"
    nii="${workdir}/nii-in/$(basename "${source}" .gz)"
  else
    cp "${source}" "${workdir}/nii-in"
    nii="${workdir}/nii-in/$(basename "${source}")"
  fi
fi

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
colourLUT "${nii}" "${zmap}" "${workdir}/cmap-out" "${age_years_dec}" "${brainage_estimation}"

### Generate and apply colour lookup tables to the zmap, then merge with the original scan
mkdir "${workdir}/qc-out"
qc=$(dirname "${zmap}")/p0$(basename "${nii}")
qcOverlay "${nii}" "${qc}" "${workdir}/qc-out"

if [[ "${dicom:-}" = "true" ]]; then
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
fi

### Cleaning up

if [[ "${dicom:-}" = "true" ]]; then
  # Copy reference DICOM file to ref_dcm.dcm and copy translation matrices to the source dir
  info "Copying reference DICOM file and translation matrices to source dir"
  cp "${ref_dcm}" "${source}/ref_dcm.dcm"
fi

# Remove the DICOM files from the source directory, but keep ref_dcm.dcm, translation matrices and log (if it exists)
if [[ "${dicom:-}" = "true" ]]; then
  if [[ "${arg_c:?}" = "1" ]]; then
    if [ -e "${source}/log" ]; then
      info "Removing everything except reference DICOM and log from the source dir. Keeping CAT12 reports."
    else
      info "Removing everything except reference DICOM from the source dir. Keeping CAT12 reports."
    fi

    find "${source}" -type f -not -name 'ref_dcm.dcm' -not -name '*.mat' -not -name 'log' -delete
    cp -a "${workdir}/nii-in/report" "${source}"
  fi

  # Keep or discard the workdir. The exit trap (see __b3bp_cleanup_before_exit) is used to discard the temporary workdir.
  if [[ "${arg_k:?}" = "1" ]]; then
    kept_workdir="${source}/$(basename ${BASH_SOURCE[0]})-workdir-$(date -u +'%Y%m%d-%H%M%S-UTC')"
    mv "${workdir}" "${kept_workdir}"
    info "Keeping temporary workdir as ${kept_workdir}"
  fi
else
  kept_workdir="$(dirname ${source})/$(basename ${source})-$(basename ${BASH_SOURCE[0]})-workdir-$(date -u +'%Y%m%d-%H%M%S-UTC')"
  mv "${workdir}" "${kept_workdir}"

  if [[ "${arg_c:?}" = "1" ]]; then
    info "Not cleaning up in NIfTI mode."
  fi
  info "Keeping temporary workdir as ${kept_workdir}"
fi