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

job_to_run="sbatch -J \"scrnaseq_${dir_name}\" -p ${slurm_partition} -n 4 --time=6-00:00:00 --mem 8G --chdir=${an_dir} -o ${an_dir}/scrna.log -e ${an_dir}/scrna.err \
--wrap=\"nextflow run $bic_scrnaseq \
-resume \
-ansi-log false \
-profile singularity \
-c $bic_scrnaseq/conf/bic/iris.conf \
--outdir ${an_dir}/cellranger_out \
--igenomes_ignore true \
--input input.csv \
--aligner cellranger \
--fasta /data1/core001/rsrc/genomic/bic/assemblies/M.musculus/mm10/mm10.fasta \
--gtf /data1/core001/rsrc/genomic/bic//annotation/M.musculus/gencode/vM23/gencode.vM23.annotation.gtf\""

echo "$job_to_run \n\n"

jobstring=$(eval $job_to_run)
# if this is unsuccessful, print error and exit
if [ $? -ne 0 ]; then
    echo "Error running job: $job_to_run"
    echo "output: $jobstring"
    exit 1
fi
