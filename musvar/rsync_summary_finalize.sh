#! /bin/bash
set -e

# This script needs to do some finalization of the pipeline. Things it will do:
# 1. Move project files to the <outdir>/project_files directory.
# 2. Run bicdelivery_summary script.
# 3. Rsync the results to the rsync directory

script_dir=$(dirname "$(realpath "$0")")

# if there is not 3 arguments, print usage and exit
if [ $# -ne 3 ]; then
    echo "Usage: rsync_summary_finalize.sh <rundir> <outdir> <rsync_dir>"
    echo "run_dir: directory where the pipeline was run (should have project files)"
    echo "out_dir: outdir provided to the pipeline"
    echo "rsync_dir: directory to rsync the results to"
    exit 1
fi

# grab rundir output, rsync dirs from command line
run_dir=$1
out_dir=$2
rsync_dir=$3

# if outdir is not a full path, add it to run_dir.
if [[ $out_dir != /* ]]; then
    out_dir=$run_dir/$out_dir
fi

#
# Move project to project_files directory
#
mkdir -p $out_dir/project_files
[[ -e $run_dir/*sample_mapping.txt ]] && cp $run_dir/*sample_mapping.txt $out_dir/project_files/
[[ -e $run_dir/*request.txt ]] && cp $run_dir/*request.txt $out_dir/project_files/
[[ -e $run_dir/input.csv ]] && cp $run_dir/input.csv $out_dir/project_files/

#
# Rsync the results to the rsync directory
#

echo "rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir"
rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir
