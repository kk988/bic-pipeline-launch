#!/bin/bash

script_dir=$(dirname "$(realpath "$0")")
sarek_dir="/juno/bic/work/kristakaz/git/bic-sarek"
profile="singularity"


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

# remove tailing / on an_dir
an_dir=$(echo $an_dir | sed 's/\/$//')

extra_args=$@

# map between request target and config filename
declare -A targets_map
targets_map["hg19"]="impact"
targets_map["hg38"]="twist"

if [ ! -f $an_dir/input.csv ]; then
    echo
    echo "Error: $an_dir/input.csv not found. This is required for the sarek pipeline"
    echo
    exit
fi

run_number=$(grep ^RunNumber $req_file | cut -f2 -d":" | tr -d " " | xargs printf "%03d" )

### targets pulled from request file
###

targets_config=$sarek_dir/conf/bic/targets/${targets}.config
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

bsub -J "MusVar_${dir_name}" -n 4 -R "rusage[mem=8]" -W 500:00 -cwd ${an_dir} -o ${an_dir}/musvar.log -e ${an_dir}/musvar.err \
nextflow run $sarek_dir/main.nf \
-profile $profile \
-ansi-log false \
-c $sarek_dir/conf/bic_musvar.config \
-c $sarek_dir/conf/juno.config \
-c $targets_config \
-work-dir ${an_dir}/work \
--genome null \
--igenomes_ignore true \
--tools freebayes,mutect2,strelka,manta \
--input ${an_dir}/input.csv \
--outdir ${an_dir}/out 

echo "MusVar pipeline submitted for analysis directory: $an_dir"