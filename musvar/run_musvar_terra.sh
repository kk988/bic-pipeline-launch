#!/bin/bash

script_dir=$(dirname "$(realpath "$0")")
sarek_dir="/juno/bic/work/kristakaz/git/bic-sarek"
profile="singularity"
rsync_only=false


# usage:
# run_musvar_terra.sh <request file> <analysis directory> <email> <rsync_dir> [extra args]
if [ $# -lt 3 ]; then
    echo "Usage: run_musvar_terra.sh <request file> <analysis directory> <email> <rsync_dir> [extra args]"
    exit 1
fi

# inputs:
# 1: request file
# 2: analysis directory (whould contain input files)
# 3: email
# 4: rsync directory
## extra args (optional)
req_file=$1
an_dir=$2
email=$3
rsync_dir=$4
shift 4

if [ "$1" == "rsync_only" ]; then
    rsync_only=true
    shift 1
fi

# remove tailing / on an_dir
an_dir=$(echo $an_dir | sed 's/\/$//')

extra_args=$@

# map between request target and config filename
declare -A targets_map
targets_map["M-IMPACT"]="impact"
targets_map["TWIST"]="twist"

if [ ! -f $an_dir/input.csv ]; then
    echo
    echo "Error: $an_dir/input.csv not found. This is required for the sarek pipeline"
    echo
    exit
fi

run_number=$(grep ^RunNumber $req_file | cut -f2 -d":" | tr -d " " | xargs printf "%03d" )

### targets pulled from request file
###
targets=$(grep ^Targets $req_file | cut -f2 -d":" | tr -d " " | xargs printf "%s" )
if [ -z "$targets" ]; then
    echo
    echo "Error: No targets found in request file. This is required for the sarek pipeline"
    echo
    exit
fi
if [ -z "${targets_map[$targets]}" ]; then
    echo
    echo "Error: Invalid targets '$targets' in request file. Valid targets are: ${!targets_map[@]}"
    echo
    exit
fi

targets_config=$sarek_dir/conf/bic/targets/${targets_map[$targets]}.config
# check targets conf dir to see if a target config exists
if [ ! -f $targets_config ]; then
    echo
    echo "Error: $targets_config not found. This is required for the sarek pipeline"
    echo
    exit
fi

export MODULEPATH=/compute/juno/bic/ROOT/opt/modulefiles:$MODULEPATH
export NXF_SINGULARITY_CACHEDIR=/juno/opt/common/bic/internal/.singularity/cache
export LD_LIBRARY_PATH=
mkdir -p ${an_dir}/work/scratch
export TMPDIR=${an_dir}/work/scratch

. /usr/share/Modules/init/bash
module load singularity/3.7.1 
module load nextflow/24.04.4 
module load java/jdk-17.0.10

dir_name=$(basename $an_dir)

if [ $rsync_only == false ]; then 
    rsync_job_hold="-w post_done(MusVar_${dir_name})"

    bsub -J "MusVar_${dir_name}" -n 4 -R "rusage[mem=8]" -W 500:00 -cwd ${an_dir} -o ${an_dir}/musvar.log -e ${an_dir}/musvar.err \
    nextflow run $sarek_dir/main.nf \
    -profile $profile \
    -ansi-log false \
    -c $sarek_dir/conf/bic/bic_musvar.config \
    -c $sarek_dir/conf/bic/juno.config \
    -c $targets_config \
    -work-dir ${an_dir}/work \
    --genome null \
    --igenomes_ignore true \
    --email_on_fail $email \
    --tools freebayes,mutect2,strelka,manta \
    --input ${an_dir}/input.csv \
    --outdir ${an_dir}/out
    
    echo "MusVar pipeline submitted for analysis directory: $an_dir"

fi

# if rsync is filled out, do finalize script
if [ -z $rsync_dir ]; then
    echo "No rsync directory provided, skipping rsync."
    exit 0
fi

export LSB_JOB_REPORT_MAIL='Y'
sleep 1

bsub -J "finalize_${dir_name}" ${rsync_job_hold} -u "${email}" -N \
-n 1 -R "rusage[mem=2]" -o ${an_dir}/rsync.log -e ${an_dir}/rsync.err \
/bin/bash ${script_dir}/rsync_summary_finalize.sh $an_dir ${an_dir}/r_${run_number} $rsync_dir