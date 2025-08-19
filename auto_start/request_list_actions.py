#! /usr/bin/env python3

# This script will go through the request list, and perform actions on tickets
import sys, os
import logging
import io
from contextlib import redirect_stdout
import re
import traceback
from config import *
from Service import Clickup
import glob
from limsETL import LIMSRequestException

def email_message(to, subject, msg): 
    """Send an email message."""
    import smtplib
    from email.mime.text import MIMEText

    msg = MIMEText(msg)
    msg['Subject'] = " ".join(["BIC_PIPELINE_LAUNCH",subject])
    msg['From'] = to
    msg['To'] = to

    with smtplib.SMTP('localhost') as server:
        server.sendmail(to, [to], msg.as_string())

def get_pipeline_data(ticket_name):
    if not ticket_name.startswith("#REQUEST"):
        logging.debug(f"Ticket {ticket_name} does not start with #REQUEST, skipping...")
        return []
    
    name = ticket_name.split("#REQUEST:")[1].strip()
    # if the name doesn't start with a REQUEST_PIPELINE_ACTIONS key, then skip it
    pipeline = [ key for key in REQUEST_PIPELINE_DATA.keys() if name.startswith(key) ]
    if not pipeline:
        logging.debug(f"Ticket {ticket_name} does not match any actionable pipelines, skipping...")
        return []
    else:
        pipeline = pipeline[0]
        logging.debug(f"Ticket {ticket_name} matches pipeline {pipeline}, checking actions...")
        return REQUEST_PIPELINE_DATA[pipeline]
    
def check_fastq(ticket, pipeline):
    fq_checked = Clickup.find_custom_field_index(ticket['custom_fields'], 'IGO Fastq Checked')
    if fq_checked is None:
        logging.debug(f"Task {ticket['name']} does not have IGO Fastq Checked field, skipping")
        return

    if "value" in ticket['custom_fields'][fq_checked] and ticket['custom_fields'][fq_checked]["value"] == 'true':
        logging.debug(f"Task {ticket['name']} had fastq checked already, skipping")
        return

    logging.debug(f"Checking FASTQ files for ticket {ticket['id']}...")
    # This function should check if it can glean IGO id from the ticket description
    # and if so, check if the fastq files are found using LIMS and nfs4_getfacl
    igo_ids_to_check = set()
    for line in ticket['description'].splitlines():
        if any(line.startswith(keyword) for keyword in CHECK_FASTQ_IGO):
            logging.debug(f"Found IGO ID line in ticket {ticket['id']}: {line}")
            igo_id_value = line.split(":", maxsplit=1)[-1].strip()
            # regex to find igo ids in the line
            igo_ids = re.findall(r'(\d{5}(?:_[a-zA-Z])?)', igo_id_value)
            if igo_ids:
                igo_ids_to_check.update(igo_ids)
                logging.debug(f"IGO IDs found: {igo_ids}")

    if not igo_ids_to_check:
        logging.debug(f"No IGO IDs found in ticket {ticket['id']}, skipping FASTQ check...")
        return
    
    # Here you would implement the logic to check if the FASTQ files exist
    import GetLIMSInfo
    import MakeProjectFiles

    has_permissions = list()
    does_not_have_permissions = list()
    logging.info(f"IGO IDs to check: {', '.join(igo_ids_to_check)} for ticket {ticket['id']}...")
    for project_id in igo_ids_to_check:
        logging.debug(f"Checking FASTQ files for IGO ID {project_id}...")
        # This function should check if the FASTQ files exist using LIMS and nfs4_getfacl
        # For now, we will just log the action
        try:
            GetLIMSInfo.run(project_id, sample_key=False)
            f = io.StringIO()
            with redirect_stdout(f):
                MakeProjectFiles.verify_mapping_permissions("Proj_%s_sample_mapping.txt" % project_id)
            out = f.getvalue()
        except LIMSRequestException as e:
            logging.error(f"Failed to get LIMS info for IGO ID {project_id}: {e}")
            Clickup.create_task_comment(ticket['id'], f"Failed to get LIMS info for IGO ID {project_id}: {e}")
            out = "BAD LIMS REQUEST"
            continue
        
        if out:
            logging.warning(f"Permissions check output for IGO ID {project_id}:\n{out}")
            does_not_have_permissions.append(project_id)
        else:
            logging.debug(f"Permissions check passed for IGO ID {project_id}.")
            has_permissions.append(project_id)

        # delete file "Proj_%s_sample_mapping.txt" % project_id when done
        os.remove("Proj_%s_sample_mapping.txt" % project_id)

    # write a comment to the ticket with the results
    comment = f"FASTQ file check results for ticket {ticket['id']}:\n"
    if has_permissions:
        comment += f"Projects with permissions: {', '.join(has_permissions)}\n"
    if does_not_have_permissions:
        comment += f"Projects POSSIBLY without permissions: {', '.join(does_not_have_permissions)}\n"
    
    logging.debug(f"Adding comment to ticket {ticket['id']}: {comment}")
    Clickup.create_task_comment(ticket['id'], comment)
    Clickup.set_custom_field(ticket['id'], UUIDS['IGO Fastq Checked'], 'true')

# ticket must be in status "ready for pipeline"
# have to check if we are to block import of project
def import_project(ticket, pipeline):
    # This function should import data into Clickup using the import script

    if ticket['status']['status'] != 'ready for pipeline':
        logging.debug(f"Ticket {ticket['id']} is not in 'Ready for Pipeline' status, skipping import...")
        return
    
    block_import_idx = Clickup.find_custom_field_index(ticket['custom_fields'], DO_NOT_IMPORT_FIELD)
    if block_import_idx is not None and "value" in ticket['custom_fields'][block_import_idx] and ticket['custom_fields'][block_import_idx]['value'].lower() == 'true':
        # If the ticket has the "Block Auto Import" field set, skip the import
        logging.debug(f"Ticket {ticket['id']} has 'Block Auto Import' field set, skipping import...")
        return

    project_path_idx = Clickup.find_custom_field_index(ticket['custom_fields'], 'ProjectFolder')
    msg = "".join([f"Ticket {ticket['id']} does not have a valid 'ProjectFolder'. Please fix",
                    " and uncheck 'Block Auto Import' to try importing again.\n\nTo manually import, ",
                    "run the import script helper found here ", MANUAL_IMPORT_SCRIPT, "."])
    if not project_path_idx or 'value' not in ticket['custom_fields'][project_path_idx] or not ticket['custom_fields'][project_path_idx]['value']:
        logging.error(f"Ticket {ticket['id']} does not have a valid 'ProjectFolder' custom field.")
        email_message(EMAIL, "Missing ProjectFolder", msg)
        Clickup.set_custom_field(ticket['id'], UUIDS['Block Auto Import'], 'true')
        return

    project_path = ticket['custom_fields'][project_path_idx]['value']
    # if path is not actually a path, error and skip import 
    # if request file is not in folder, error and skip import
    if not os.path.exists(project_path):
        logging.error(f"Project path {project_path} does not exist for ticket {ticket['id']}.")
        email_message(EMAIL, "Invalid ProjectFolder Path", msg)
        Clickup.set_custom_field(ticket['id'], UUIDS['Block Auto Import'], 'true')
        return
    
    request_file = glob.glob(os.path.join(project_path, PROJECT_DATA[pipeline]['request_file_glob']))
    if not request_file:
        logging.error(f"No request file found in {project_path} for ticket {ticket['id']}.")
        email_message(EMAIL, "Missing Request File", msg)
        Clickup.set_custom_field(ticket['id'], UUIDS['Block Auto Import'], 'true')
        return

    logging.info(f"Importing data for ticket {ticket['id']}...")
    # Run the import script
    cmd = f"{PROJECT_DATA[pipeline]['import_script']} {request_file[0]}"
    if 'import_script_args' in PROJECT_DATA[pipeline]:
        cmd += f" {PROJECT_DATA[pipeline]['import_script_args']}"
    logging.debug(f"Running command: {cmd}")
    f = io.StringIO()
    with redirect_stdout(f):
        return_code = os.system(cmd)
    out = f.getvalue()
    logging.debug("Command finished")
    logging.debug(f"Command output:\n{out}")
    #Clickup.add_comment(ticket['id'], f"Import script output:\n{out}")

    if return_code != 0:
        msg = f"Import script failed for ticket {ticket['id']} with return code {return_code}.\n\nOutput:\n{out}"
        logging.error(f"Import script failed for ticket {ticket['id']}. Return code: {return_code}")
        email_message(EMAIL, "Import Script Failed", msg)
        Clickup.set_custom_field(ticket['id'], UUIDS['Block Auto Import'], 'true')
        return
    logging.debug(f"Import script completed successfully for ticket {ticket['id']}.")

    # change status of ticket to submitted to pipeline
    logging.debug(f"Changing status of ticket {ticket['id']} to 'Submitted to Pipeline'...")
    Clickup.update_task(ticket['id'], {'status': 'submitted to pipeline'})

def tag_project(ticket, pipeline):
    if "tag_name" not in PROJECT_DATA[pipeline]:
        logging.error(f"No tag name specified for pipeline {pipeline}. Cannot tag project.")
        return
    
    if "tags" in ticket:
        tags_present = [tag['name'] for tag in ticket['tags']]
        if PROJECT_DATA[pipeline]['tag_name'] in tags_present:
            logging.debug(f"Ticket {ticket['id']} already has tag '{PROJECT_DATA[pipeline]['tag_name']}', skipping...")
            return

    logging.info(f"Adding tag '{PROJECT_DATA[pipeline]['tag_name']}' to ticket {ticket['id']}...")
    Clickup.add_tag_to_task(ticket['id'], PROJECT_DATA[pipeline]['tag_name'])
    
    return


if __name__ == "__main__":
    logging.basicConfig(level=LOG_LEVEL)

    # grab open tickets from the request list
    logging.debug("Fetching open tickets from the request list...")
    body = {'include_closed': 'false' }
    open_items = Clickup.get_tasks(REQUEST_LIST_ID, body=body)
    
    for ticket in open_items['tasks']:
        ticket_id = ticket['id']
        logging.debug(f"Processing ticket {ticket_id}...")
        
        # Check if the ticket has any possible actions
        pdata = get_pipeline_data(ticket['name'])
        actions = pdata['actions'] if pdata else None

        if not actions:
            logging.debug(f"No actions found for ticket {ticket_id}, skipping...")
            continue

        for action in actions:
            logging.debug(f"Performing action '{action}' on ticket {ticket_id}...")

            # Perform the action based on the action type
            function_to_call = globals()[action]
            try:
                function_to_call(ticket, pdata['pipeline'])
            except Exception as e:
                logging.error(f"Error performing action '{action}' on ticket {ticket_id}: {e}")
                traceback.print_exc()
                continue
            logging.debug(f"Action '{action}' completed for ticket {ticket_id}.")

    logging.debug("All tickets processed.")

    # Exit the script
    sys.exit(0)