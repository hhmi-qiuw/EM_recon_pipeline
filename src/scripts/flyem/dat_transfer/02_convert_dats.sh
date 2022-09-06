#!/bin/bash

set -e

umask 0002

if (( $# < 3 )); then
  echo "USAGE $0 <transfer info file> <num workers> <parent work_dir> [first_dat] [last_dat]"
  exit 1
fi

TRANSFER_INFO="$1"
NUM_WORKERS="$2"
PARENT_WORK_DIR="$3"

if [[ "${HOSTNAME}" =~ ^(e05u15|e05u16) ]]; then
  echo "ERROR: running on login1 or login2, need to bsub this job first ..."
  exit 1
fi

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_converter.py"
ARGS="${ARGS} --volume_transfer_info ${TRANSFER_INFO}"
ARGS="${ARGS} --num_workers ${NUM_WORKERS}"
ARGS="${ARGS} --parent_work_dir ${PARENT_WORK_DIR}"

if (( $# > 2 )); then
  ARGS="${ARGS} --first_dat ${3}"
  if (( $# > 3 )); then
    ARGS="${ARGS} --last_dat ${4}"
  fi
fi

#ARGS="${ARGS} --lsf_runtime_limit 23:59"
ARGS="${ARGS} --lsf_runtime_limit 3:59"

echo """
On ${HOSTNAME} at ${RUN_DATE_AND_TIME}

Running:
  python ${ARGS}
"""

# The exit status of a pipeline is the exit status of the last command in the pipeline,
# unless the pipefail option is enabled (see The Set Builtin).
# If pipefail is enabled, the pipeline's return status is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

python ${ARGS} 2>&1
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}