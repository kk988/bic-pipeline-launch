#!/bin/bash

slurm_partition="cmobic_cpu,cmobic_pipeline"
bic_scdownstream="/data1/core001/work/bic/kazmierk/git/bic-scdownstream"
an_dir=$(pwd | sed 's/\/$//')


export MODULEPATH=/etc/modulefiles:/usr/share/modulefiles:/admin/software/lmod/modulefiles:/admin/software/spack/spack_modulefiles/Core
export MODULEPATH_ROOT=/usr/share/modulefiles
export MODULESHOME=/usr/share/lmod/lmod
mkdir -p ${an_dir}/work/scratch
export TMPDIR=${an_dir}/work/scratch
export NXF_SINGULARITY_CACHEDIR=/usersoftware/core001/common/bic/internal/.singularity/cache

. /usr/share/lmod/lmod/init/bash
module load openjdk/17.0.11_9

dir_name=$(basename $an_dir)

nextflow=/data1/core001/work/bic/kazmierk/nextflow/25.10.0/nextflow

job_to_run="sbatch -J \"scdownstream_${dir_name}\" -p ${slurm_partition} -n 4 --time=6-00:00:00 --mem 8G --chdir=${an_dir} -o ${an_dir}/scdownstream.log -e ${an_dir}/scdownstream.err \
--wrap=\"$nextflow run $bic_scdownstream \
-resume \
-ansi-log false \
-profile singularity \
-c $bic_scdownstream/conf/bic/iris.config \
--outdir ${an_dir}/downstream_out \
--ambient_correction cellbender \
--input downstream_input.csv \
--liana_resource_name mouseconsensus\""


echo "$job_to_run \n\n"

jobstring=$(eval $job_to_run)
# if this is unsuccessful, print error and exit
if [ $? -ne 0 ]; then
    echo "Error running job: $job_to_run"
    echo "output: $jobstring"
    exit 1
fi
