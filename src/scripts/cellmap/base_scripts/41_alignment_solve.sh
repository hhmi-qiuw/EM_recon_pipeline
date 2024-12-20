#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker ...

export N_EXECUTORS_PER_NODE=2 # 6
export N_CORES_PER_EXECUTOR=5 # 5
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

if (( $# < 1 )); then
  STACK_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}"
  SECTION_COUNT=$(curl -s "${STACK_URL}" | ${JQ} '.stats.sectionCount')
  SECTIONS_PER_SOLVE_SET=500
  NUMBER_OF_LEFT_SOLVE_SETS=$(( (SECTION_COUNT / SECTIONS_PER_SOLVE_SET) + 1 ))
  NUMBER_OF_RIGHT_SOLVE_SETS=$(( NUMBER_OF_LEFT_SOLVE_SETS - 1 ))
  NUMBER_OF_SOLVE_SETS=$(( NUMBER_OF_LEFT_SOLVE_SETS + NUMBER_OF_RIGHT_SOLVE_SETS ))
  TASKS_PER_NODE=$(( N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR ))
  N_NODES=$(( (NUMBER_OF_SOLVE_SETS / TASKS_PER_NODE) + 1 ))
  echo "
Default number of worker nodes is ${N_NODES}:
  ${ACQUIRE_TRIMMED_STACK} has ${SECTION_COUNT} z layers
  ${NUMBER_OF_SOLVE_SETS} solve sets will be processed given ${SECTIONS_PER_SOLVE_SET} z layers per set
"
else
  N_NODES="${1}"        # 18
fi

#-----------------------------------------------------------
ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${ACQUIRE_TRIMMED_STACK}"
ARGS="${ARGS} --targetStack ${ALIGN_STACK}"
ARGS="${ARGS} --matchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxNumMatches 0"
ARGS="${ARGS} --completeTargetStack"
ARGS="${ARGS} --blockSize 500"
#ARGS="${ARGS} --blockSize 120"
ARGS="${ARGS} --blockOptimizerLambdasRigid 1.0,1.0,0.9,0.3,0.01"
ARGS="${ARGS} --blockOptimizerLambdasTranslation 1.0,0.0,0.0,0.0,0.0"
ARGS="${ARGS} --blockOptimizerIterations 1000,1000,500,250,250"
ARGS="${ARGS} --blockMaxPlateauWidth 250,250,150,100,100"
ARGS="${ARGS} --maxPlateauWidthGlobal 50"
ARGS="${ARGS} --maxIterationsGlobal 10000"
ARGS="${ARGS} --dynamicLambdaFactor 0.0"
ARGS="${ARGS} --threadsWorker 1"
ARGS="${ARGS} --threadsGlobal ${N_CORES_DRIVER}"

ARGS="${ARGS} --minStitchingInliers 1000000" # exclude stitch first processing by setting minStitchingInliers ridiculously high
#ARGS="${ARGS} --customSolveClass org.janelia.render.client.solver.custom.SolveSetFactoryBRSec34"

# --noStitching
# --minZ 1 --maxZ 38068
# --serializerDirectory .
# --serializeMatches

# must export this for flintstone
export RUNTIME="333:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.solver.DistributedSolveSpark"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/solve-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS
} 2>&1 | tee -a "${LOG_FILE}"

SHUTDOWN_JOB_ID=$(awk '/PEND.*_sd/ {print $1}' "${LOG_FILE}")

if (( SHUTDOWN_JOB_ID > 1234 )); then
  echo "Scheduling z correction derivation job upon completion of solve job ${SHUTDOWN_JOB_ID}"
  echo

  bsub -P "${BILL_TO}" -J "${RENDER_PROJECT}_launch_z_corr" -w "ended(${SHUTDOWN_JOB_ID})" -n1 -W 59 "${SCRIPT_DIR}"/support/42_gen_z_corr_run.sh launch
fi
