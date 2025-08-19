#! /bin/bash
set -e

script_dir=$(dirname "$(realpath "$0")")


export MODULEPATH=/compute/juno/bic/ROOT/opt/modulefiles:$MODULEPATH

. /usr/share/Modules/init/bash
module load singularity/3.7.1 

singularity exec -B /juno -B /igo -B /usr/bin/nfs4_getfacl /opt/common/bic/internal/project_file_generation/pfg.simg python ${script_dir}/request_list_actions.py

