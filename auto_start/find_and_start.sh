#! /bin/bash
set -e

script_dir=$(dirname "$(realpath "$0")")


export MODULEPATH=/compute/juno/bic/ROOT/opt/modulefiles:$MODULEPATH

. /usr/share/Modules/init/bash
module load singularity/3.7.1 

singularity exec -B /juno -B /igo /opt/common/bic/internal/project_file_generation/pfg.simg python ${script_dir}/find_and_start_runs.py

