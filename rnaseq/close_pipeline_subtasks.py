from Service import Clickup
import os
import sys
import importlib.util

config_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../auto_start/config.py'))
spec = importlib.util.spec_from_file_location("automation_config", config_path)
automation_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(automation_config)
import logging
import argparse

def get_args():
    parser = argparse.ArgumentParser(description="Close ClickUp tasks for RNAseq pipeline subtasks.")
    parser.add_argument('--ticket_id', required=True, help='ClickUp ticket ID')
    parser.add_argument('--rnaseq_ver', required=True, help='RNAseq pipeline version')
    parser.add_argument('--rsync_dir', required=True, help='Directory to rsync summary files to')
    parser.add_argument('--del_path', required=True, help='Path to final results directory')
    parser.add_argument('--diff_ver', help='Diff pipeline version')
    parser.add_argument('--comments', help='Comments for the ClickUp ticket')
    parser.add_argument('--log_level', default='INFO', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'], help='Logging level')
    parser.add_argument('--dry_run', action='store_true', help='Perform a dry run without making changes')
    return parser.parse_args()

def update_custom_fields(task_id, fields, task_fields, dry_run):
    if dry_run:
        logging.info(f"Dry run: Would update task {task_id} with fields {fields}")
    else:
        for key, value in fields.items():
            if key in task_fields and "value" in task_fields[key] and task_fields[key]["value"] == value:
                logging.info(f"Field {key} already set to {value}, skipping update.")
                continue
            
        Clickup.set_custom_field(task_id, task_fields[key]['id'], value)
        logging.info(f"Updated task {task_id} with fields {fields}")

if __name__ == "__main__":
    args = get_args()

    logging.basicConfig(level=args.log_level)
    logger = logging.getLogger(__name__)

    # Add comments to counts task
    # but if comments need to be added, close without updating or closing anything
    if args.comments:
        if not args.dry_run:
            Clickup.create_task_comment(args.ticket_id, args.comments)
        logger.info(f"Added comment to task {args.ticket_id} - exiting without updating fields or closing tasks")
        sys.exit(0)
    
    # grab task info, parent, and cfs
    curr_task = Clickup.get_task(args.ticket_id)
    task_cf = Clickup.format_field_map({"fields": curr_task["custom_fields"]})
    parent_id = curr_task.get('parent', None)
    
    # update custom fields for counts task
    fields_to_update = {
        "Archive Path" : args.rsync_dir,
        "Pipeline Version": f"bic-rnaseq: {args.rnaseq_ver}"
    }
    update_custom_fields(args.ticket_id, fields_to_update, task_cf, args.dry_run)

    # close task
    if not args.dry_run:
        Clickup.update_task(args.ticket_id, {"status": "closed"})

    # find other open subtasks from parent
    parent = Clickup.get_task(parent_id)

    # NOTE: There will be a bug here when there are more than one acceptable "siblings_to_start"
    valid_siblings = [ subtask['id'] for subtask in parent['subtasks'] if any(ticket in subtask['name'] for ticket in automation_config.PROJECT_DATA["RNASEQ"]['siblings_to_start']) ]

    for sibling_id in valid_siblings:
        sibling_task = Clickup.get_task(sibling_id)
        sibling_cf = Clickup.format_field_map({"fields": sibling_task["custom_fields"]})
        if sibling_task['status'] != 'closed':
            fields_to_update = {
                "Archive Path" : args.rsync_dir,
                "Pipeline Version": f"bic-differentialabundance: {args.diff_ver}"
            }
            update_custom_fields(sibling_id, fields_to_update, sibling_cf, args.dry_run)
            if not args.dry_run:
                Clickup.update_task(sibling_id, {"status": "closed"})

    # update delivery dir on parent
    parent_cf = Clickup.format_field_map({"fields": parent["custom_fields"]})
    fields_to_update = {
        "Delivery Path": args.del_path
    }
    update_custom_fields(parent_id, fields_to_update, parent_cf, args.dry_run)