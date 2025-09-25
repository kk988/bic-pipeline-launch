# Automation

This code will (hopefully) be able to automate any pipeline from CLICKUP request to run on the pipeline. 

## Overview
Currently the code works as such:

### run_request_list_actions.sh
This is a helper script that goes through open `#REQUEST` tickets and runs some actions on them.

Python code `request_list_actions.py` is a script that is run inside the [Project File Generation](https://github.com/cBio-MSKCC/project_file_generation)(PFG) container on the server. This code will utilize the `Clickup` service in PFG code to query all open tickets in our `#REQUEST` task list. It will cycle through each ticket, and if it's name has a specific pipeline in it (see keys `REQUEST_PIPELINE_DATA` in config), it will run through the actions associated with that pipeline. 

Current actions include:
- import_project - imports given project into another list where the actual pipeline is run (sometimes automatically).
- tag_project - adds a tag to said task. This was done so that clickup automation could take over (auto-assigning). This may be retired soon since clickup has some new features that could probably handle this.
- check_fastq - check that BIC has permissions to this fastq. Write the results to said clickup task

### find_and_start.sh

This is a helper script which will allow you to run the matching python script on crontab. Example crontab to start this is here:
``` 
MAILTO="<your msk email>"

# runs every hour at the 1st minute
1 * * * * /path/to/bic-pipeline-launch/auto_start/find_and_start.sh
```

Python code `find_and_start_runs.py` is a script that is run inside the [Project File Generation](https://github.com/cBio-MSKCC/project_file_generation)(PFG) container on the server. This code will utilize the `Clickup` service in PFG code to query any Clickup lists in your config file to see if there are any `TODO` tickets under your user. If so, it will go through a number of checks to make sure the ticket should be automated, gather information from that ticket, parent ticket, and information about sibling tickets. Then on the server, it will verify there is no issue with running this project and set up a project folder. Then it will write the command that needs to be executed to a "queue file" (designated in the configuration). Finally, if everything works, it will send an email to the user, change status of the ticket and any sibling tickets it needs to open, and fill out the `runPath` and `archivePath`.

If there is a problem with processing the task, the field `Email Alerted` checkbox is checked in the Clickup ticket, and an email is sent to the user saying what went wrong. This checkbox signals that `find_and_start_runs.py` should not process this ticket, even if it is a valid ticket to process. **note:** if this happens, and you fix the problem, simply uncheck the `Email Alerted` checkbox in the clickup ticket. Sibling tickets will not have the `Email Alerted` checkbox checked.

### run_queue

This script will grab and run any commands in the queue file. An example crontab to start this is here:
```
MAILTO="<your msk email>"

# this will run every hour at the 10th minute
10 * * * * /path/to/bic-pipeline-launch/auto_start/run_queue.sh /path/to/run_queue.txt 
```

Script will grab the first line in the queue, will execute the line, and then delete the line in the queue if everything worked correctly. This script should exit if the executed command did not work. Currently there is no email to the user if something goes wrong. We will have to change that.

## Setup
1. To set up this code, checkout the code into a local place where you can run it. 
2. Checkout a specific tag - releases on the github will (hopefully) tell you which version will run which version of what pipeline. 
3. Copy `config.py.dist` from this directory to `config.py` - then fill out the information required
    - To create a api token from clickup follow the directions [here](https://help.clickup.com/hc/en-us/articles/6303426241687-Use-the-ClickUp-API#personal-api-key)
4. Set up your crontabs using the examples above. 
5. Double check for issues running this. Create a clickup ticket or something...

### Grabbing clickup user ID
User ID is needed for the config file, but is non-trivial to grab from clickup. The easiest way to grab clickup id is through the API examples:

``` 
#!/bin/bash
# requires curl and jq
# if you don't have jq, just print the response and manually grab
# the user id.

# Replace this with your actual ClickUp API token
API_TOKEN="your_clickup_api_token"

# Make the API request to get user info
response=$(curl -s -H "Authorization: $API_TOKEN" "https://api.clickup.com/api/v2/user")

# Extract and print the user ID using jq
user_id=$(echo "$response" | jq -r '.user.id')

# Output the result
if [[ "$user_id" != "null" ]]; then
    echo "Your ClickUp user ID is: $user_id"
else
    echo "Failed to fetch user ID. Check your API token."
fi
```

## Restarting project
Here are some scenarious of what to do if you get an error.

### Project already has a folder in your work/archive dir
If a project has a directory in your work or archive path you should get an email during the `find_and_start.sh` script. The script will send you an email, and check off a checkbox on the clickup field `Email Alerted`. To fix this issue, remove the offending directory, then uncheck the `Email Alerted` field on the clickup ticket. 

### The pipeline dies. 
If the pipeline dies for some reason and you have to restart it, it'll probably be best to restart it manually. To do that you should run `run_rnaseq_terra.sh <request file> <analysis directory> <email> <rsync_dir> [DE_only or rsync_only]` for more information on how to run the pipeline manually, check [the clickup documentation](https://app.clickup.com/9006020830/v/dc/8ccty6y-2053/8ccty6y-3273). If you only have to restart DE (not from beginning) use `DE_only` option. If you have to restart the finalize/rsync portion of the pipeline (post DE) use `rsync_only` option.

### Totally restart the automation of a project.
If your project is finished or running, and you need to restart the automation, to do this you need to clear some stuff. 
- Delete any project folder in your work dir and rsync dir.
- Don't have to, but you should clear the fields that were filled out in the ticket (and sibling tickets) when autostart began (ex: RunPath, ArchivePath)
- Change Ticket (counts most likely) and sibling tickets to the `TODO` status
- If `Email Alerted` is checked off, uncheck it.