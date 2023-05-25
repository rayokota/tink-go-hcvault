#!/bin/bash
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# Utility script to optionally run a command optionally in a new container.
#
# This script must be run from inside the Tink library to run the command for.
#
# NOTE: When running in a new container, this sctips mounts the parent folder of
# `pwd`. Other dependencies, if any, are assumed to be located there. For
# example, if running tink-py tests, this script assumes:
#   - pwd => /path/to/parent/tink-py
#   - mount path => /path/to/parent
#   - ls /path/to/parent => tink_cc tink_py.

set -eo pipefail

usage() {
  cat <<EOF
Usage:  $0 [-c <container image>] [-k <service key file path>] <command>
  -c: [Optional] Container image to run the command on.
  -k: [Optional] Service key file path for pulling the image from the Google Artifact Registry (https://cloud.google.com/artifact-registry).
  -h: Help. Print this usage information.
EOF
  exit 1
}

# Args.
COMMAND=

# Options.
CONTAINER_IMAGE_NAME=
GCR_SERVICE_KEY_PATH=

#######################################
# Process command line arguments.
#######################################
process_args() {
  # Parse options.
  while getopts "hc:k:" opt; do
    case "${opt}" in
      c) CONTAINER_IMAGE_NAME="${OPTARG}" ;;
      k) GCR_SERVICE_KEY_PATH="${OPTARG}" ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly CONTAINER_IMAGE_NAME
  readonly GCR_SERVICE_KEY_PATH
  readonly COMMAND=("$@")
}

main() {
  process_args "$@"

  if [[ -z "${CONTAINER_IMAGE_NAME:-}" ]]; then
    echo "Running command on the host"
    set -x
    time "${COMMAND[@]}"
  else
    echo "Running command on a new container from image ${CONTAINER_IMAGE_NAME}"
    if [[ ! -z "${GCR_SERVICE_KEY_PATH:-}" ]]; then
      # Activate service account to read from a private artifact registry repo.
      gcloud auth activate-service-account --key-file="${GCR_SERVICE_KEY_PATH}"
      gcloud config set project tink-test-infrastructure
      gcloud auth configure-docker us-docker.pkg.dev --quiet
    fi
    set -x
    local -r path_to_mount="$(dirname "$(pwd)")"
    local -r library_to_test="$(basename "$(pwd)")"
    time docker pull "${CONTAINER_IMAGE_NAME}"
    time docker run \
      --mount type=bind,src="${path_to_mount}",dst=/deps \
      --workdir=/deps/"${library_to_test}" \
      --rm \
      "${CONTAINER_IMAGE_NAME}" \
      bash -c "$(echo "${COMMAND[@]}")"
  fi
}

main "$@"
