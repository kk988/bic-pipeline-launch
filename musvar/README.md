# Musvar 
(bic-sarek with musvar config)

These scripts are used to run musvar pipeline, which is bic-sarek pipeline, with additional musvar steps.

## Setup analysis folder
Setting up a project folder requires these things:
1. `input.csv` - a csv file with the input for the pipeline. Current input.csv format require these colums: `patient,sample,status,lane,fastq_1,fastq_2` and the description of the columns is described here: https://nf-co.re/sarek/3.5.1/docs/usage/#input-sample-sheet-configurations 

2. `Proj_xxxx_request.txt` file. This is required for the main bic-sarek pipeline, as well as finalization and rsyncing. An example with the *REQUIRED* fields are shown here:
``` 
Project_ID: Proj_100000
PI: soccin
Investigator: soccin
RunNumber: 12
Build: mm39
Targets: M-IMPACT
```
Currently available builds: mm38, mm39
Currently available targets: M-IMPACT, TWIST

## Running

To run from scratch. 
`Usage: run_musvar_terra.sh <request file> <analysis directory> <email> <rsync_dir> [extra args]`

Where:
- Request file is the full path to the request file
- Analysis directory is the full path to the analysis folder, where input.csv and the request.txt file is
- Email is your mskcc email
- Rsync_dir is the directory where the project folder should be rsynced to for local archiving, NOT delivery (ex: `/ifs/rtsia01/bic/users/kristakaz/rnaseq`)
- Extra args are optional arguments that may change over time
    - Currently the only optional argument is 'rsync_only' - this can be used if rsync step failed, but the pipeline finished correctly.

The pipeline will run and will email you though nextflow if it errors out for some reason. If the pipeline is successful (and you provide rsync directory) you will recieve an email through server when the rsync has completed whether or not it is successful. This script will also output a file to the analysis directory provided with the setup and command used to run the pipeline. You *should* be able to `mv musvar_cmd.txt musvar_cmd.sh && chmod +x musvar_cmd.sh` and then run it as a bash script to rerun the pipeline command. 

## Rerunning

Currently there is no fast way to `resume` the bic-sarek pipeline. Nextflows `-resume` key does nothing because usually the intermediate files are deleted at the end of the pipeline run (need to look into this). However, I have been able to run the pipeline from step variant calling which helps skip the initial alignment. 

When `run_musvar_<server>.sh` runs, it will output a file to the `analysis directory` called `musvar_cmd.txt` with the nextflow command that was run. In order to start the pipeline at the variant calling step, add `--step 'variant_calling'` to the end of the nextflow command and change `--input <analysis_directory>/input.csv` to `--input <analysis_directory>/<outdir>/csv/recalibrated.csv`. *note* this will NOT run the full automated analysis, just the analysis step. In order to continue automation after pipeline reruns succesfully, run `run_musvar_<server>.sh` with "extra arg" `rsync_only`. 