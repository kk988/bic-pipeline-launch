#!/usr/bin/env python

# This script is used to perform post-pipeline checks on RNA-seq data to ensure that the files are in the correct format and contain the expected data.

""" 
Post-pipeline checks for RNA-seq data
Files present: 
- MultiQC report
- Merged counts
- DE: Report.html
- DE: GSEA results

Permissions:
Ensure file permissions are set correctly for the user running the pipeline.

- Genome in request.txt file == Genome that was run
- All samples were aligned - need to add exception for alignment failures
- all samples are found in the merged counts file
- Counts has correct genome annotation
- DE: results found for all groups in grouping file
- DE: unfiltered DE results > 1 line
"""

import os
import sys
import logging
import glob
import json

logging.basicConfig(level=logging.INFO)


# CONSTANTS FOR FILE PATHS
multiqc_report = "metrics/multiqc/star_htseq/multiqc_report.html"
merged_counts_file = "star_htseq/htseq/htseq.merged.counts.tsv"
de_tables_dir = "star_htseq/differentialExpression_gene/tables/differential/"
de_full_table_suffix = ".deseq2.de_results.tsv"
de_filtered_table_suffix = ".deseq2.de_results_filtered.tsv"
de_report_dir = "star_htseq/differentialExpression_gene/report/"
de_gsea_dir = "star_htseq/differentialExpression_gene/report/gsea/"
request_glob = "*_request.txt"
contrasts_glob = "contrasts*.csv"
params_glob = "pipeline_info/params_*.json"

genome_map = {"hg19":"hg19_local",
              "hg38":"hg38_local",
              "mm10":"mm10_local",
              "mm39":"mm39_local"}

def check_file_exists(file_path):
    """Check if a file exists."""
    if not os.path.isfile(file_path):
        logging.error(f"File {file_path} does not exist.")
        return False
    return True

def perform_de_checks(req_data, odir, contrast_files):
    """Perform checks specific to differential expression results."""
    error_found = False

    # Check that each contrast file has a corresponding DE report html
    for contrast_file in contrast_files:
        contrast_name = os.path.basename(contrast_file).replace(".csv", "")
        if not check_file_exists(os.path.join(odir, de_report_dir, f"{contrast_name}.html")):
            error_found = True
            continue

        # for each line in contrast file, check if DE table exists (full and filtered)
        # ensure that full table has more than one line
        with open(contrast_file, 'r') as cf:
            for line in cf:
                if line.strip() and not line.startswith('#') and not line.startswith('id'):
                    comparison_name = line.split(',')[0]

                    de_result_file = os.path.join(odir, de_tables_dir, f"{comparison_name}{de_full_table_suffix}")
                    de_filtered_file = os.path.join(odir, de_tables_dir, f"{comparison_name}{de_filtered_table_suffix}")

                    if not check_file_exists(de_filtered_file):
                        error_found = True

                    if not check_file_exists(de_result_file):
                        error_found = True
                    else:   
                        with open(de_result_file, 'r') as df:
                            linecount = 0
                            for _ in df:
                                linecount += 1
                                if linecount > 1:
                                    break
                            if linecount <= 1:
                                logging.error(f"DE results file {de_result_file} is empty or has no results.")
                                error_found = True

                    # GSEA - check that this softlink is a file that exists
                    gsea_links = glob.glob(os.path.join(odir, de_gsea_dir, f"{comparison_name}.*.index.html"))
                    if not gsea_links:
                        logging.error(f"No GSEA report links found for comparison {comparison_name}.")
                        error_found = True
                    if len(gsea_links) > 1:
                        logging.warning(f"Multiple GSEA report links found for comparison {comparison_name}.")
                    for gsea_link in gsea_links:
                        if not os.path.isfile(gsea_link):
                            logging.error(f"GSEA report link {gsea_link} is not a valid file.")
                            error_found = True

    return not error_found

def get_pipeline_genome(odir):
    """ Get genome from pipeline's param file
        Note: this just picks the first params file, not the latest one.
    """
    params_file = glob.glob(os.path.join(odir, params_glob))
    if not params_file:
        logging.error(f"No params file found in {odir}.")
        return None

    # load json file, gather genome key value
    params_file = params_file[0]
    with open(params_file, 'r') as pf:
        params = json.load(pf)
        if "genome" in params:
            return params["genome"]
    logging.error("Genome not found in params file.")
    return None

def perform_checks(req_data, wdir):
    error_found = False

    odir = "r_%03d" % (int(req_data["RunNumber"]))

    """Perform all post-pipeline checks."""
    # Check for required files
    if not check_file_exists(os.path.join(odir, multiqc_report)):
        error_found = True
    if not check_file_exists(os.path.join(odir, merged_counts_file)):
        error_found = True
    if not check_file_exists(os.path.join(odir, merged_counts_file)):
        error_found = True

    # Check DE results
    contrast_files = glob.glob(os.path.join(wdir, contrasts_glob))

    if contrast_files: 
        if not perform_de_checks(req_data, odir, contrast_files):
            error_found = True

    # Check genome consistency
    expected_genome = req_data["Build"]
    if not expected_genome:
        expected_genome = req_data["Species"]
    if not expected_genome:
        logging.error("Genome not specified in request file.")
        error_found = True

    pipeline_genome = get_pipeline_genome(odir)
    if expected_genome not in genome_map:
        logging.error(f"Expected genome '{expected_genome}' not found in genome_map.")
        error_found = True
    elif genome_map[expected_genome] != pipeline_genome:
        logging.error(f"Genome mismatch: expected {genome_map[expected_genome]}, but got {pipeline_genome}.")
        error_found = True

    # Additional checks can be added here as needed

    if error_found:
        logging.error("Post-pipeline checks failed.")
        sys.exit(1)
    else:
        logging.info("All post-pipeline checks passed successfully.")


if __name__ == "__main__":
    # If there is one argument, use it as a path to working directory
    if len(sys.argv) == 2:
        wdir = sys.argv[1]
    else:
        wdir = os.getcwd()

    # grab request.txt file
    request_file = glob.glob( os.path.join(wdir, request_glob))
    if not request_file:
        logging.error(f"No request files found matching pattern {os.path.join(wdir, request_glob)}.")
        sys.exit(1)

    request_file = request_file[0]
    logging.info(f"Found request file: {request_file}")

    # parse request file - key : value
    req_data = {}
    with open(request_file, 'r') as req:
        for line in req:
            if line.strip() and not line.startswith('#'):
                key, value = line.split(':')
                req_data[key.strip()] = value.strip()
    
    perform_checks(req_data, wdir)
