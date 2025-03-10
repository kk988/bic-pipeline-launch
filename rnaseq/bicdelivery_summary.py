#!/usr/bin/env python

#Command line args: 
# 1. output_dir

import os
import sys
import json
import glob
import pandas as pd
import shutil

#
# set a bunch of vars
#
#PATHS
proj_file_dir = "project_files"
multiqc_data_dir = "metrics/multiqc/star_htseq/multiqc_report_data/"
multiqc_plot_dir = "metrics/multiqc/star_htseq/multiqc_report_plots/png/"
bicdelivery_summary_dir = "pipeline_info/bicdelivery_summary"
de_dir =  "star_htseq/differentialExpression_gene/tables/differential/"
gsea_path = "star_htseq/differentialExpression_gene/report/gsea/"
de_project_qc_plot_dir1 = "star_htseq/differentialExpression_gene/plots/exploratory/"
de_project_qc_plot_dir2 = "png/"
de_comparison_qc_plots = "star_htseq/differentialExpression_gene/plots/differential/"
#GLOBS
contrast_glob = proj_file_dir + "/contrasts*.csv"
#OTHER
gsea_FDR_cutoff = 0.25
gsea_FDR_header = "FDR q-val"
de_fold_change_header = "log2FoldChange"
contrast_id_col = "id"
contrast_target_col = "target"
contrast_ref_col = "reference"
contrast_var_col = "variable"
input_sample_col = "sample"

multiqc_data_reqs = {
    "general": "multiqc_general_stats.txt"
}
multiqc_plot_reqs = {
    "multiqc_alignment": "star_alignment_plot-cnt.png",
}

# add to contrast object the data from the DE files
# gsea, and qc plots
def gather_contrast_data(output_dir, contrasts):
    for contrast in contrasts:
        # DE data
        # Open filtered .tsv file, grab # genes up and down 
        # and add to contrasts
        de_res = pd.read_csv(os.path.join(output_dir, de_dir, contrast + ".deseq2.results_filtered.tsv"), sep="\t")
        contrasts[contrast]["DE_up"] = de_res[de_res[de_fold_change_header] >= 0].shape[0]
        contrasts[contrast]["DE_down"] = de_res[de_res[de_fold_change_header] < 0].shape[0]

        # GSEA data
        contrasts[contrast]['GSEA'] = {}

        gsea_datasets = os.listdir(os.path.join(output_dir, gsea_path, contrast))

        for dataset in gsea_datasets:
            contrasts[contrast]['GSEA'][dataset] = {}
            target_filename = os.path.join(output_dir, gsea_path, contrast, dataset, ".".join([contrast, dataset, "gsea_report_for_" + contrasts[contrast]['target'], "tsv"]))
            reference_filename = os.path.join(output_dir, gsea_path, contrast, dataset, ".".join([contrast, dataset, "gsea_report_for_" + contrasts[contrast]['reference'], "tsv"]))
            if not os.path.exists(target_filename):
                target_filename = os.path.join(output_dir, gsea_path, contrast, dataset, ".".join([contrast, dataset, "gsea_report_for_na_pos","tsv"]))
                reference_filename = os.path.join(output_dir, gsea_path, contrast, dataset, ".".join([contrast, dataset, "gsea_report_for_na_neg","tsv"]))
                if not os.path.exists(target_filename):
                    print("Target GSEA file not found: " + target_filename)
                    sys.exit(1)
            t_report = pd.read_csv(target_filename, sep="\t")
            r_report = pd.read_csv(reference_filename, sep="\t")
            contrasts[contrast]['GSEA'][dataset][contrasts[contrast]['target'] + "_enriched_pathways" ] = t_report[t_report[gsea_FDR_header] < gsea_FDR_cutoff].shape[0]
            contrasts[contrast]['GSEA'][dataset][contrasts[contrast]['reference'] + "_enriched_pathways" ] = r_report[r_report[gsea_FDR_header] < gsea_FDR_cutoff].shape[0]
            contrasts[contrast]['GSEA'][dataset]['index'] = os.path.join(gsea_path, contrast, dataset, ".".join([contrast, dataset,"index", "html"]))

        # DE comparison qc plots
        contrasts[contrast]["plots"] = glob.glob( os.path.join(output_dir, de_comparison_qc_plots, contrast,"png","*.png"))
        # iterate plots paths and remove output dir
        contrasts[contrast]["plots"] = [ plot.replace(output_dir + "/", "") for plot in contrasts[contrast]["plots"] ]

    return contrasts

# gather project metrics -
# 1. multiqc data
# 2. multiqc plots
# 3. DE project qc plots
def gather_project_metrics(output_dir):
    proj_metrics = {}
    proj_metrics["data"] = {}
    proj_metrics["plots"] = {}

    # copy files to pipeline_info_dir since these aren't rsync'd
    copy_to_dir = os.path.join(output_dir, bicdelivery_summary_dir)
    os.makedirs(copy_to_dir, exist_ok=True)
    for key in multiqc_data_reqs:
        shutil.copy(os.path.join(output_dir, multiqc_data_dir, multiqc_data_reqs[key]), copy_to_dir)
        proj_metrics["data"][key] = os.path.join(bicdelivery_summary_dir, multiqc_data_reqs[key])
    for key in multiqc_plot_reqs:
        shutil.copy(os.path.join(output_dir, multiqc_plot_dir, multiqc_plot_reqs[key]), copy_to_dir)
        proj_metrics["plots"][key] = os.path.join(bicdelivery_summary_dir, multiqc_plot_reqs[key])

    # for each variable in de_project_qc_plot_dir1, 
    # grab the files in de_project_qc_plot_dir2
    # and add to proj_metrics
    proj_metrics["comparison_set_qc"] = {}
    for var in os.listdir(os.path.join(output_dir, de_project_qc_plot_dir1)):
        proj_metrics["comparison_set_qc"][var] = []
        for plot in os.listdir(os.path.join(output_dir, de_project_qc_plot_dir1, var, de_project_qc_plot_dir2)):
            proj_metrics["comparison_set_qc"][var].append(os.path.join(de_project_qc_plot_dir1, var, de_project_qc_plot_dir2, plot))

    return proj_metrics

## NOTE: This assumes that contrast id is unique across all input files
## Our code as of right now should ensure they are unique
## but this is a potential point of failure - esp with DE reruns.
def parse_contrasts(contrast_file, contrasts):
    with open(contrast_file, "r") as f:
        header = f.readline().strip().split(",")
        # id variable reference target blocking
        contrast_id_idx = header.index(contrast_id_col)
        contrast_target_idx = header.index(contrast_target_col)
        contrast_ref_idx = header.index(contrast_ref_col)
        contrast_var_idx = header.index(contrast_var_col)

        for line in f:
            cols = line.strip().split(",")
            contrasts[cols[contrast_id_idx]] = {"reference": cols[contrast_ref_idx], 
                                                "target": cols[contrast_target_idx], 
                                                "variable": cols[contrast_var_idx]}
    return contrasts
            
def pull_sample_groups(input_file, variables, samp_dict):

    with open(input_file, "r") as f:
        header = f.readline().strip().split(",")
        sample_id_idx = header.index(input_sample_col)

        for line in f:
            cols = line.strip().split(",")
            samp = cols[sample_id_idx]
            if samp not in samp_dict:

                # This dict will have samples and their associated groups for comparisons
                samp_dict[samp] = { var: cols[header.index(var)] for var in variables }
            else :
                for var in variables:

                    # if var is in sample dict (not likely) make sure the value is the same
                    if var in samp_dict[samp]:
                        if samp_dict[samp][var] != cols[header.index(var)]:
                            print("Sample " + samp + " has conflicting values for variable " + var)
                            sys.exit(1)
                    else:
                        samp_dict[samp][var] = cols[header.index(var)]
    return samp_dict
            

# if main 
if __name__ == "__main__":

    # Read the command line args
    output_dir = sys.argv[1]

    # remove trailing slash
    output_dir = output_dir.rstrip("/")

    # usage
    if len(sys.argv) != 2:
        print("Usage: bicdelivery_summary.py <output_dir>")
        sys.exit(1)

    # Check if the output directory exists
    if not os.path.exists(output_dir):
        print("Output directory does not exist")
        sys.exit(1)

    input_file = os.path.join(output_dir, proj_file_dir, "input.csv")
    if not os.path.exists(input_file):
        print("Input file not found: " + input_file)
        sys.exit(1)

    contrast_files = glob.glob(os.path.join(output_dir, contrast_glob))

    samples = {}
    contrasts = {}
    # Read contrasts files
    # populate fields in res_obj
    # have ot add output_dir to input file path
    for contrast_file in contrast_files:

        contrasts = parse_contrasts(contrast_file, contrasts)

        # grab the variable from contrast keys
        variables = set( [ contrasts[contrast]["variable"] for contrast in contrasts.keys() ] )
        samples = pull_sample_groups( input_file, variables, samples)

    # get project specific metrics
    proj_metrics = gather_project_metrics(output_dir)

    # gather contrast data
    contrasts = gather_contrast_data(output_dir, contrasts)

    ## collect the output.
    res_obj = {}
    res_obj["samples"] = samples
    res_obj["project_metrics"] = proj_metrics
    res_obj["contrasts"] = contrasts

    bicsummary_file = os.path.join(output_dir, proj_file_dir, "bicdelivery_summary.json")
    with open(bicsummary_file, "w") as f:
        json.dump(res_obj, f, indent=4)
    print("Summary file written to " + bicsummary_file)
    sys.exit(0)



