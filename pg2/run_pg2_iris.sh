#!/usr/bin/sh

set -e

host=$(hostname)
user=$(whoami)
script_dir=$(dirname "$(realpath "$0")")

if [ $host != "islogin01.mskcc.org" ] ; then
    echo "As of right now, this script must be run on islogin01.mskcc.org."
    exit 1
fi

#
# Modify and uncomment ALL variables below. Script will not run without all values set!
#

pg2_refs_dir=/data1/core001/rsrc/apps/pg2
repo_dir=/data1/core001/work/bic/kazmierk/git/ProteomeGenerator2
slurm_partition="cmobic_cpu,cmobic_pipeline"

export PATH=${pg2_refs_dir}/miniconda3/bin:${pg2_refs_dir}/arriba_v1.2.0:$PATH

# input 
an_dir=$1
samp_name=$2
email=$3

if [ $# -lt 3 ]; then
    echo "Usage: run_pg2_iris.sh <analysis directory> <sample name> <email> "
    exit 1
fi

# remove tailing / on an_dir
an_dir=$(echo $an_dir | sed 's/\/$//')
mkdir -p ${an_dir}/scratch/${user}
export TMPDIR=${an_dir}/scratch

CONFIG=${an_dir}/config_${samp_name}.yaml
TARGET=out/experiment/novel_analysis/proteome_blast.outfmt6
LOG=${an_dir}/snakemake_run_${samp_name}.out
CLUSTER="sbatch -J {params.J} -p ${slurm_partition} -n {params.n} --nodes=1 --time=6-00:00:00 --mem-per-cpu {params.mem_per_cpu}G -o {params.o} -e {params.eo}" 
BINDS="--bind /data1:/data1"

job_to_run="sbatch -J \"pg2_${samp_name}\" -p ${slurm_partition} -n 4 --time=6-00:00:00 --nodes=1 --mem 8G --chdir=${an_dir} \
    --mail-user=${email} --mail-type=END,FAIL -o ${an_dir}/pg2.log -e ${an_dir}/pg2.err \
    --wrap=\"snakemake --snakefile ${repo_dir}/ProteomeGenerator2.py \
  --configfile ${CONFIG} \
  --cluster '${CLUSTER}' \
  -j 100 \
  -k \
  --ri \
  --latency-wait 30 \
  --use-conda \
  --use-singularity \
  --singularity-args '${BINDS}' \
  ${TARGET} \
  > ${LOG} 2>&1\""

echo "$job_to_run \n\n"
jobstring=$(eval $job_to_run)
if [ $? -ne 0 ]; then
    echo "Error running job: $job_to_run"
    echo "output: $jobstring"
    exit 1
fi
