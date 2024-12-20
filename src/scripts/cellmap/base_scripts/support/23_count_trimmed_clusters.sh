#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
SCRIPT_DIR=$(dirname "${SCRIPT_DIR}") # move up one directory since this is in support subdirectory
source "${SCRIPT_DIR}"/00_config.sh

LOG_DIR="${SCRIPT_DIR}/logs"
COUNT_LOG="${LOG_DIR}/cluster_count.${ACQUIRE_TRIMMED_STACK}.log"

mkdir -p "${LOG_DIR}"

ARGS="org.janelia.render.client.ClusterCountClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ACQUIRE_TRIMMED_STACK}"
ARGS="${ARGS} --matchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxSmallClusterSize 0 --includeMatchesOutsideGroup --maxLayersPerBatch 1000 --maxOverlapLayers 6"
ARGS="${ARGS} --maxLayersForUnconnectedEdge 50"

echo "
Connected tile cluster counts will be written to:
  ${COUNT_LOG}

Be patient, this could take a few minutes ...
"

# shellcheck disable=SC2086
${RENDER_CLIENT_SCRIPT} 1G ${ARGS} > "${COUNT_LOG}"

tail -15 "${COUNT_LOG}"