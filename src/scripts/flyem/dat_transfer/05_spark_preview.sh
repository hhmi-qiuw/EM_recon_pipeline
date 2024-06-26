#!/bin/bash

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

# Set up LSF
source /misc/lsf/conf/profile.lsf

# loading LSF profile returns error code, so need to wait until here to set -e
set -e

if (( $# < 1 )); then
  echo "USAGE $0 <transfer JSON directory>     e.g. /groups/flyem/home/flyem/bin/dat_transfer/2022/config"
  exit 1
fi

TRANSFER_JSON_DIR="${1}"
if [ ! -d "${TRANSFER_JSON_DIR}" ]; then
  echo "ERROR: ${TRANSFER_JSON_DIR} is not a directory"
  exit 1
else
  echo "Using transfer JSON directory: ${TRANSFER_JSON_DIR}"
fi

cd "${TRANSFER_JSON_DIR}"
TRANSFER_JSON_FILES=$(ls volume_transfer_info.*.json)
if [ -z "${TRANSFER_JSON_FILES}" ]; then
  echo "ERROR: no volume_transfer_info JSON files found in ${TRANSFER_JSON_DIR}"
  exit 1
fi

#-----------------------------------------------------------
# Setup parameters used for all Spark jobs ...

export JAVA_HOME="/misc/sc/jdks/zulu11.56.19-ca-jdk11.0.15-linux_x64"
export PATH="${JAVA_HOME}/bin:${PATH}"

JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.n5.H5TileToN5PreviewClient"

# Avoid "Could not initialize class ch.systemsx.cisd.hdf5.CharacterEncoding" exceptions
# (see https://github.com/PreibischLab/BigStitcher-Spark/issues/8 ).
H5_LIBPATH="-Dnative.libpath.jhdf5=/groups/flyem/data/render/lib/jhdf5/native/jhdf5/amd64-Linux/libjhdf5.so"
export SUBMIT_ARGS="--conf spark.executor.extraJavaOptions=${H5_LIBPATH} --conf spark.driver.extraJavaOptions=${H5_LIBPATH}"

# setup for 11 cores per worker (allows 4 workers to fit on one 48 core node with 4 cores to spare for other jobs)
export N_EXECUTORS_PER_NODE=5
export N_CORES_PER_EXECUTOR=2
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

# preview code needs newer GSON library to parse HDF5 attributes
export SUBMIT_ARGS="${SUBMIT_ARGS} --conf spark.executor.extraClassPath=/groups/flyTEM/flyTEM/render/lib/gson-2.10.1.jar"

#-----------------------------------------------------------
# Loop over all transfer JSON files and launch Spark job for each one ...

JQ="/groups/flyem/data/render/bin/jq"

for TRANSFER_JSON_FILE in ${TRANSFER_JSON_FILES}; do

  EXPORT_PREVIEW_VOLUME_COUNT=$(grep -c "EXPORT_PREVIEW_VOLUME" "${TRANSFER_JSON_FILE}")

  if (( EXPORT_PREVIEW_VOLUME_COUNT == 1 )); then

    RENDER_HOST=$(${JQ} -r '.render_data_set.connect.host' "${TRANSFER_JSON_FILE}")
    RENDER_PORT=$(${JQ} -r '.render_data_set.connect.port' "${TRANSFER_JSON_FILE}")
    ALIGN_H5_PATH=$(${JQ} -r '.cluster_root_paths.align_h5' "${TRANSFER_JSON_FILE}")
    BILL_TO=$(${JQ} -r '.cluster_job_project_for_billing' "${TRANSFER_JSON_FILE}")
    NUM_WORKERS=$(${JQ} -r '.number_of_preview_workers // "10"' "${TRANSFER_JSON_FILE}") # default to 10 workers

    if [ -d "${ALIGN_H5_PATH}" ]; then

      ARGS="--baseDataUrl http://${RENDER_HOST}:${RENDER_PORT}/render-ws/v1"
      ARGS="${ARGS} --transferInfo ${TRANSFER_JSON_DIR}/${TRANSFER_JSON_FILE}"

      # must export this for flintstone
      export LSF_PROJECT="${BILL_TO}"

      LOG_DIR="${ALIGN_H5_PATH}/logs"
      SPARK_LOG_DIR="${LOG_DIR}/spark"
      mkdir -p "${SPARK_LOG_DIR}"

      LAUNCH_LOG_FILE="${LOG_DIR}/preview-$(date +"%Y%m%d_%H%M%S").log"

      # ensure all workers are available before starting driver
      export MIN_WORKERS="${NUM_WORKERS}"

      # Write spark logs to backed-up filesystem rather than user home so that they are readable by others for analysis.
      # NOTE: must consolidate logs when changing run parent dir
      export SPARK_JANELIA_ARGS="--consolidate_logs --run_parent_dir ${SPARK_LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "Running with arguments:
${ARGS}
"
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $NUM_WORKERS $JAR $CLASS $ARGS
} 2>&1 | tee -a "${LAUNCH_LOG_FILE}"

    else
      echo "${TRANSFER_JSON_FILE} cluster_root_paths.align_h5 ${ALIGN_H5_PATH} does not exist, nothing to do"
    fi

  else
    echo "${TRANSFER_JSON_FILE} does not contain EXPORT_PREVIEW_VOLUME task, nothing to do"
  fi

done




