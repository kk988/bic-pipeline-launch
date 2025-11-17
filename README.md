# bic-pipeline-launch

Repo that should hold scripts to start the steps of the pipeline. This should include getting the pipelines started, and post pipeline actions. Post-pipeline actions should only be actions that don't make sense to have in the pipeline.

## Pipelines

### MusVar
Musvar is the mouse variants pipeline. It utilizes nf-sarek as well as a number of added modules. Read `musvar/README.md` for more information about running this pipeline.

### RNASeq
RNASeq analysis pipeline consists of nf-rnaseq and nf-diffabundance Nextflow workflows as well as a number of additional modules. It runs on terra, running at iris is still in testing. Read `rnaseq/README.md` for more information about running this pipeline.

## Automation

There is some automation scripts in `auto_start` which will automatically start the rnaseq pipeline on terra. Read `auto_start/README.md` for more information about it. 