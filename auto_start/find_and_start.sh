#! /bin/bash
set -e

script_dir=$(dirname "$(realpath "$0")")

singularity exec -B /data1/core001 -B /ifs -B /usr/bin/nfs4_getfacl \
/usersoftware/core001/common/bic/internal/project_file_generation/pfg.simg \
python ${script_dir}/find_and_start_runs.py

