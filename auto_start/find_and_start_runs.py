from Service import Clickup
import logging
import glob
import shutil
import os
import fcntl
import time

# hopefully this will overwrite the config that is imported from PFG
from config import *

# script will search every list in the config file - for open tasks 
# that are assigned to the user id in the config file. If the title
# matches a specific wording, it will start the task, add a comment,
# and add the fields that needed to be added.

def append_to_file_safely(file_path, content, max_retries=4, retry_delay=4):
    retries = 0
    while retries < max_retries:
        try:
            with open(file_path, 'a') as file:
                # Try to acquire the lock without blocking
                fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
                file.write(content + '\n')
                # Unlock the file after writing
                fcntl.flock(file, fcntl.LOCK_UN)
                return  # Exit the function after successful write
        except BlockingIOError:
            # Handle the case where the file is locked
            print(f"File {file_path} is currently locked. Retrying... ({retries + 1}/{max_retries})")
            retries += 1
            time.sleep(retry_delay)
    # If we reach here, all retries failed
    email_message(EMAIL, f"Failed to write to {file_path}", f"Failed to write to {file_path} after {max_retries} retries.")
    logging.error(f"Failed to write to {file_path} after {max_retries} retries.")
    raise RuntimeError(f"Failed to write to {file_path} after {max_retries} retries.")

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

# copy files - not directories from src to dest
def copy_all_files(src_dir, dest_dir):
    for filename in os.listdir(src_dir):
        src_file = os.path.join(src_dir, filename)
        dest_file = os.path.join(dest_dir, filename)
        if os.path.isfile(src_file):
            shutil.copy2(src_file, dest_file)

def run_create_nf_files(pipeline, run_path, task, strand, build):
    # run the create_nf_files script
    mapping = glob.glob(os.path.join(run_path, PROJECT_DATA[pipeline]['mapping_glob']))
    sample_key = glob.glob(os.path.join(run_path, PROJECT_DATA[pipeline]['sample_key_glob']))
    sample_comp = glob.glob(os.path.join(run_path, PROJECT_DATA[pipeline]['sample_comp_glob']))

    optional_args = ""

    # mapping and request files must exist, and there must be only one
    if len(mapping) != 1:
        logging.error(f"One mapping file NOT found in {run_path}")
        email_message(EMAIL, f"One mapping file NOT found in {run_path}", f"No mapping file, or too many mapping files found in {run_path}. You must do this manually.")
        Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
        return False

    if len(sample_key) > 0:
        optional_args +=  " --key " + " ".join( sorted(sample_key) )
    if len(sample_comp) > 0:
        optional_args += " --comparisons " + " ".join( sorted(sample_comp) )
    
    # build command
    cmd = f"{PROJECT_DATA[pipeline]['create_nf_files']} -m {mapping[0]}  -s {strand} -b {build} --dir {run_path} {optional_args}"

    logging.debug(f"Running command: {cmd}")
    return_code = os.system(cmd)
    logging.debug("Command finished")
    if return_code != 0:
        logging.error(f"Command {cmd} failed with return code {return_code}")
        email_message(EMAIL, f"Command {cmd} failed", f"Command {cmd} failed with return code {return_code}. You must do this manually.")
        Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
        return False
    return True

def start_pipeline(run_path, pipeline, task):
    # run the pipeline
    # grab reqeust file 
    request_file = glob.glob(os.path.join(run_path, PROJECT_DATA[pipeline]['request_file_glob']))
    if len(request_file) != 1:
        logging.error(f"One request file NOT found in {run_path}")
        email_message(EMAIL, f"One request file NOT found in {run_path}", f"No request file, or too many request files found in {run_path}. You must do this manually.")
        Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
        return False
    
    script_to_run = os.path.join( os.path.dirname(os.path.abspath(__file__)),PROJECT_DATA[pipeline]['bic_launch_relpath']) 

    cmd = f"{script_to_run} {request_file[0]} {run_path} {EMAIL} {PROJECT_DATA[pipeline]['rsync_dir']} > {run_path}/start_pipeline.log 2>&1"
    logging.debug(f"Adding command to queue: {cmd}")
    # append to the queue file
    append_to_file_safely(RUN_QUEUE, cmd)
    logging.debug("Command added to queue")
    return True

if __name__ == '__main__':
    logging.basicConfig(level=LOG_LEVEL)
    logging.debug("Starting script to find and start runs")

    for pipeline in CLICKUP_LIST_ID:
        logging.debug(f"Searching list {pipeline}")
        body = {
            'assignees[]': [CLICKUP_USER_ID],
            'statuses[]': ['to do'],
            'include_closed': 'false',
            'subtasks': 'true'
        }
        todo_tasks = Clickup.get_tasks(CLICKUP_LIST_ID[pipeline], body)
        if len(todo_tasks['tasks']) > 0:
            logging.info(f"Found {len(todo_tasks['tasks'])} tasks in list {pipeline}")

        for task in todo_tasks["tasks"]:
            logging.info(f"Checking task {task['name']}")
            # if task name ends with any of the acceptable tickets
            # let's pretty print the results.
            if any(ticket in task['name'] for ticket in PROJECT_DATA[pipeline]['acceptable_tickets']):
                logging.info(f"Found task {task['name']} in list {pipeline}")
                
                # get the parent task, if there is no parent task, skip 
                parent_id = task.get('parent', None)
                if parent_id is None:
                    logging.info(f"Task {task['name']} has no parent task, skipping")
                    continue

                # if task has email alerted field set to true, skip
                email_alerted_idx = Clickup.find_custom_field_index(task['custom_fields'], 'Email Alerted')
                if email_alerted_idx is None:
                    logging.info(f"Task {task['name']} does not have Email Alerted field, skipping")
                    continue

                if "value" in task['custom_fields'][email_alerted_idx] and task['custom_fields'][email_alerted_idx]["value"] == 'true':
                    logging.info(f"Task {task['name']} has emailed user, already, skipping")
                    continue

                parent = Clickup.get_task(parent_id)
                logging.debug(f"Parent task {parent['name']} found")

                # record parent task name, 
                # record sibling tasks whose name ends with a value in sibling_to_start
                project_name = parent['name']
                valid_siblings = [ subtask['id'] for subtask in parent['subtasks'] if any(ticket in subtask['name'] for ticket in PROJECT_DATA[pipeline]['siblings_to_start']) ]

                parent_fields = Clickup.format_field_map({'fields': parent['custom_fields']})
                project_path = parent_fields['ProjectFolder']["value"]
                build = parent_fields['Build']["value"].lower()
                strand = parent_fields['Strand']["value"].lower()
                if strand == "none":
                    strand = "unstranded"

                if 'Comments' in parent_fields.keys() and PROJECT_DATA[pipeline]['manual_pipeline_comment'] in parent_fields['Comments']:
                    logging.info(f"Task {task['name']} has a manual pipeline comment, skipping")
                    email_message(EMAIL, f"Task {task['name']} has a manual pipeline comment", f"Task {task['name']} has a manual pipeline comment. You must do this manually.")
                    Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
                    continue
                
                # make sure RunPath is not already made
                run_path = f"{PROJECT_DATA[pipeline]['work_dir']}/{project_name}"
                if os.path.exists(run_path):
                    logging.info(f"Run path {run_path} already exists, skipping")
                    email_message(EMAIL, f"Run path {run_path} already exists", f"Run path {run_path} already exists. You must do this manually.")
                    Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
                    continue

                logging.debug(f"Run path {run_path} will be created")
                # make run path - copy files from project_path to run path
                os.makedirs(run_path, exist_ok=True)
                copy_all_files(project_path, run_path)
                # write task id to a file in run_path
                with open(f"{run_path}/clickup_task_id.txt", 'w') as f:
                    f.write(task['id'] + '\n')
                logging.debug(f"Run path {run_path} created; project files copied")

                rsync_dir = PROJECT_DATA[pipeline]['rsync_dir']
                # make sure the project run number isn't already in the archive dir
                if ":" in PROJECT_DATA[pipeline]['rsync_dir']:
                    rsync_dir = PROJECT_DATA[pipeline]['rsync_dir'].split(":")[1]
                # make sure the project run number isn't already in the archive dir
                archive_path = f"{rsync_dir}/{project_name}/r_00{parent_fields['RunNumber']['value']}"
                logging.debug(f"Archive path {archive_path} should not be present")
                if os.path.exists(archive_path):
                    logging.info(f"Archive path {archive_path} already exists, skipping")
                    email_message(EMAIL, f"Archive path {archive_path} already exists", f"Archive path {archive_path} already exists. You must do this manually.")
                    Clickup.set_custom_field(task['id'], UUIDS['Email Alerted'], 'true')
                    continue

                # I think this means we are OKAY to start the pipeline!
                logging.info(f"Starting pipeline for task {task['name']}")

                # step one - run pfg to nf script
                if "create_nf_files" in PROJECT_DATA[pipeline]:
                    logging.debug(f"Running {PROJECT_DATA[pipeline]['create_nf_files']}")
                    
                    nf_file_create = run_create_nf_files(pipeline, run_path, task, strand, build)
                    if not nf_file_create:
                        logging.error(f"create_nf_files failed for task {task['name']}")
                        continue
                    
                bic_launch = start_pipeline(run_path, pipeline, task)

                if not bic_launch:
                    logging.error(f"bic_launch failed for task {task['name']}")
                    continue
                # step two - "start" task and sibling tasks.
                # update custom fields
                inprogress = {"status": "in progress"}
                Clickup.update_task(task['id'], inprogress)
                Clickup.set_custom_field(task['id'], UUIDS['Run Path'], run_path)
                Clickup.set_custom_field(task['id'], UUIDS['Archive Path'], f"{rsync_dir}/{project_name}")

                # update parent task to in progress
                Clickup.update_task(parent_id, inprogress)

                for sibling in valid_siblings:
                    logging.debug(f"Starting sibling task {sibling}")
                    Clickup.update_task(sibling, inprogress)
                    Clickup.set_custom_field(sibling, UUIDS['Run Path'], run_path)
                    Clickup.set_custom_field(sibling, UUIDS['Archive Path'], f"{rsync_dir}/{project_name}")

                # step three - send start pipeline email
                msg = f"Pipeline added to queue for {task['name']} in {run_path}. Archive path is {rsync_dir}/{project_name}. \n\n"
                email_message(EMAIL, f"Pipeline started for task {task['name']}", msg)

                


