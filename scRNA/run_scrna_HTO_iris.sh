#!/bin/bash

slurm_partition="cmobic_cpu,cmobic_pipeline"
bic_scrnaseq="/data1/core001/work/bic/kazmierk/git/bic-scrnaseq"
an_dir=$(pwd | sed 's/\/$//')


export MODULEPATH=/etc/modulefiles:/usr/share/modulefiles:/admin/software/lmod/modulefiles:/admin/software/spack/spack_modulefiles/Core
export MODULEPATH_ROOT=/usr/share/modulefiles
export MODULESHOME=/usr/share/lmod/lmod
mkdir -p ${an_dir}/work/scratch
export TMPDIR=${an_dir}/work/scratch
export NXF_SINGULARITY_CACHEDIR=/usersoftware/core001/common/bic/internal/.singularity/cache

. /usr/share/lmod/lmod/init/bash
module load nextflow/24.10.0  
module load openjdk/17.0.11_9

dir_name=$(basename $an_dir)

job_to_run="sbatch -J \"scrnaseq_${dir_name}\" -p ${slurm_partition} -n 12 --time=6-00:00:00 --nodes=1 --mem 72G --chdir=${an_dir} -o ${an_dir}/scrna.log -e ${an_dir}/scrna.err \
--wrap=\"singularity exec -B /data1 -B /usersoftware/core001 /usersoftware/core001/common/bic/internal/.singularity/cache/quay.io-nf-core-cellranger-8.0.0.img \
cellranger count --id=17877 \
--transcriptome=/data1/core001/work/bic/kazmierk/scrnaseq/Proj_B-102-331/cellranger_out/cellranger/mkref/cellranger_reference \
--libraries=${an_dir}/libraries.csv \
--feature-ref=${an_dir}/feature_ref.csv \
--localcores=12 \
--localmem=72 \
--create-bam=true  > ${an_dir}/cellranger_count.log 2>&1\""




echo "$job_to_run \n\n"

jobstring=$(eval $job_to_run)
# if this is unsuccessful, print error and exit
if [ $? -ne 0 ]; then
    echo "Error running job: $job_to_run"
    echo "output: $jobstring"
    exit 1
fi
