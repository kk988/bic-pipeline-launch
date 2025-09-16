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
- Rsync_dir is the directory where the project folder should be rsynced to
- Extra args are optional arguments that may change over time
    - Currently the only optional argument is 'rsync_only' - this can be used if rsync step failed, but the pipeline finished correctly.

## Rerunning

Currently there is no fast way to rerun the bic-sarek pipeline. Nextflows -resume key does nothing because usually the intermediate files are deleted at the end of the pipeline run, successful or not (I think because they are too big). However, I have been able to run the pipeline from step variant calling which helps skip the initial alignment. 

When `run_musvar_<server>.sh` runs, it will output a file to the `analysis directory` called `musvar_cmd.txt` with the nextflow command that was run. There are some setup 