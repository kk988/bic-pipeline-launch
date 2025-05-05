#!/bin/bash

host=$(hostname)
script_dir=$(dirname "$(realpath "$0")")

if [ $host != "terra" ] && [ $host != "zeta" ]; then
    echo "As of right now, this script must be run on terra or zeta."
    exit 1
fi

# constants
bic_rnaseq="/juno/opt/common/bic/internal/bic-rnaseq/current"
bic_diff="/juno/opt/common/bic/internal/bic-differentialabundance/current"
profile="singularity"
DE_only=false
rsync_only=false


# usage:
# run_rnaseq.sh <request file> <analysis directory> <email> <rsync_dir> [DE_only] [extra args]
if [ $# -lt 3 ]; then
    echo "Usage: run_rnaseq.sh <request file> <analysis directory> <email> <rsync_dir> [DE_only or rsync_only] [extra args]"
    exit 1
fi

# inputs:
# 1: request file
# 2: analysis directory (whould contain input files)
# 3: email
# 4: rsync directory
# 4: DE_only (optional)
## extra args (optional)
req_file=$1
an_dir=$2
email=$3
rsync_dir=$4
shift 4

# remove tailing / on an_dir
an_dir=$(echo $an_dir | sed 's/\/$//')

if [ "$1" == "DE_only" ]; then
    DE_only=true
    shift 1
fi

if [ "$1" == "rsync_only" ]; then
    rsync_only=true
    shift 1
fi

extra_args=$@

# genome map contains all the local genomes that are available as of now
# To add another genome, set up the genome in the nextflow.config files
# for both rnaseq and diff, and add the mapping here
declare -A genome_map
genome_map["hg19"]="hg19_local"
genome_map["hg38"]="hg38_local"
genome_map["mm10"]="mm10_local"
genome_map["mm39"]="mm39_local"

run_number=$(grep ^RunNumber $req_file | cut -f2 -d":" | tr -d " " | xargs printf "%03d" )

## get stuff that is needed from request file
build=$(grep ^Build $req_file | cut -f2 -d":" | tr -d " ")
if [ -z $build ]; then
    echo "Could not find build in request file."
    exit 1
fi

if [[ -z ${genome_map[$build]} ]]; then
    echo "Could not find genome mapping for $build.\n"
    echo "To add another genome, set up the genome in the nextflow.config files for both rnaseq and diff, and add the mapping in this script."
    exit 1
fi

genome=${genome_map[$build]}

## COMMAND...

export MODULEPATH=/compute/juno/bic/ROOT/opt/modulefiles:$MODULEPATH
export LD_LIBRARY_PATH=
mkdir -p ${an_dir}/work/scratch
export TMPDIR=${an_dir}/work/scratch
export NXF_SINGULARITY_CACHEDIR=/juno/opt/common/bic/internal/.singularity/cache

. /usr/share/Modules/init/bash
module load singularity/3.7.1 
module load nextflow/24.04.4 
module load java/jdk-17.0.10

dir_name=$(basename $an_dir)

de_job_hold=""
rsync_job_hold=""
# if DE_only is false and rsync only is false, run the rnaseq pipeline
if [ $DE_only == false ] && [ $rsync_only == false ]; then
    rsync_job_hold="-w post_done(rnaseq_${dir_name})"
    de_job_hold="-w post_done(rnaseq_${dir_name})" 

    ## RNASEQ

    bsub -J "rnaseq_${dir_name}" -n 4 -R "rusage[mem=8]" -W 300:00 -cwd ${an_dir} -o ${an_dir}/rnaseq.log -e ${an_dir}/rnaseq.err \
nextflow run $bic_rnaseq \
-resume \
-profile $profile \
-ansi-log false \
-c $bic_rnaseq/conf/bic.config \
-params-file $bic_rnaseq/params/params.bic.yml \
-w ${an_dir}/work \
--genome ${genome} \
--input ${an_dir}/input.csv \
--outdir ${an_dir}/r_${run_number}  

else
    # make dir if it doesn't exist yet
    mkdir -p ${an_dir}/r_${run_number}
fi

# if rnaseq_only is false, run DIFF
if [ $rsync_only == false ]; then
    cnum=0
    ## DIFF
    for cfile in $(ls $an_dir/contrasts*.csv 2> /dev/null); do
        sleep 1
        # change job hold to the previous diff job
        if [ $cnum -gt 0 ]; then
            de_job_hold="-w post_done(diff_${dir_name}_${cnum})"
        fi

        cnum=$((cnum+1))
        if [ -f $cfile ]; then
            gsea=""
            rsync_job_hold="-w post_done(diff_${dir_name}_${cnum})"
            if [ -f $an_dir/gsea_gene_sets.txt ];then
                gene_lists=$(cat $an_dir/gsea_gene_sets.txt | tr "\n" "," | sed 's/,$//') 
                gsea=" --gsea_run true --gene_sets_files $gene_lists "
                export NXF_SINGULARITY_HOME_MOUNT=true
            fi 
        fi

        cword=$(basename $cfile .csv)

        bsub -J "diff_${dir_name}_${cnum}" -n 4 -R "rusage[mem=8]" -W 300:00 -cwd ${an_dir} $de_job_hold -o ${an_dir}/diff.log -e ${an_dir}/diff.err \
    nextflow run $bic_diff \
    -profile $profile \
    -resume \
    -ansi-log false \
    -c $bic_diff/conf/bic.config \
    -params-file $bic_diff/params/params.bic.yml \
    -w ${an_dir}/work \
    --email_on_fail $email \
    --input ${an_dir}/input.csv \
    --matrix ${an_dir}/r_${run_number}/star_htseq/htseq/htseq.merged.counts.tsv \
    --contrasts ${cfile} \
    --study_name ${cword} \
    --genome ${genome} \
    ${gsea} \
    --outdir ${an_dir}/r_${run_number}/star_htseq/differentialExpression_gene 

    done
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





