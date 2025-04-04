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
panda_simg="/juno/bic/depot/singularity/pandas/pandas.simg"

# if outdir is not a full path, add it to run_dir.
if [[ $out_dir != /* ]]; then
    out_dir=$run_dir/$out_dir
fi

#
# softlink gsea report index.html to outdir
#
curr_pwd=$(pwd)
# if gsea report directory exists, create a softlink to the index.html file
if [ -d ${out_dir}/star_htseq/differentialExpression_gene/report/gsea ]; then
    echo "GSEA report directory exists, creating softlink to index.html"
    cd ${out_dir}/star_htseq/differentialExpression_gene/report/gsea;
    ln -s */*/*index.html .
    cd $curr_pwd
fi

#
# Move project to project_files directory
#
mkdir -p $out_dir/project_files
cp $run_dir/*sample_mapping.txt $run_dir/*request.txt $run_dir/input.csv $out_dir/project_files/

# Check if files matching the pattern exist and copy them if they do
if ls $run_dir/*sample_key*txt 1>/dev/null 2>&1; then
    cp $run_dir/*sample_key*txt $out_dir/project_files/
fi

if ls $run_dir/*sample_comparison*txt 1>/dev/null 2>&1; then
    cp $run_dir/*sample_comparison*txt $out_dir/project_files/
fi

if ls $run_dir/contrasts*csv 1>/dev/null 2>&1; then
    cp $run_dir/contrasts*csv $out_dir/project_files/
fi

#
# Run bicdelivery_summary script
#
. /usr/share/Modules/init/bash
module load singularity/3.7.1 
singularity exec -B /juno:/juno $panda_simg python ${script_dir}/bicdelivery_summary.py $out_dir

#
# Rsync the results to the rsync directory
#

echo "rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir"
rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir

