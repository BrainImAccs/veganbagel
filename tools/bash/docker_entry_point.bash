#!/usr/bin/env bash

cat <<EOF

 This container takes a directory with DICOM files of a 3D T1w structural MRI brain
 scan and generates a map of regional volume changes in relation to an age- and
 sex-matched cohort of pre-processed normal scans.

 When no arguments are given, the container will start in daemon mode and listen
 for incoming DICOM connections.

 More help may be found when starting the container with the "--help" argument.

EOF

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if any arguments have been passed
if [ "$#" -eq 0 ]; then
  bash "${__dir}/../../BrainSTEM/incoming/incoming.bash" &
  bash "${__dir}/../../BrainSTEM/received/queue.bash" &
  wait
else
  "${__dir}/../../veganbagel.bash" "$@"
fi 
