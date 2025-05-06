# Automation

This code will (hopefully) be able to automate any pipeline from CLICKUP request to run on the pipeline. 

## Overview
Currently the code works as such:

### find_and_start.sh

This is a helper script which will allow you to run the matching pythong script on crontab. Example crontab to start this is here:
``` 
# runs every hour at the 1st minute
1 * * * * /path/to/bic-pipeline-launch/auto_start/find_and_start.sh
```

Python code `find_and_start_run.py` is a script that is run inside the [Project File Generation](https://github.com/cBio-MSKCC/project_file_generation)(PFG) container on the server. This code will utilize the `Clickup` service in PFG code to query any Clickup lists in your config file to see if there are any `TODO` tickets under your user. If so, it will go through a number of checks to make sure the ticket should be automated, gather information from that ticket, parent ticket, and information about sibling tickets. Then on the server, it will verify there is no issue with running this project and set up a project folder. Then it will write the command that needs to be executed to a "queue file" (designated in the configuration). Finally, if everything works, it will send an email to the user, change status of the ticket and any sibling tickets it needs to open, and fill out the `runPath` and `archivePath`.

If there is a problem with processing the task, the field `Email Alerted` checkbox is checked in the Clickup ticket, and an email is sent to the user saying what went wrong. This checkbox signals that `find_and_start_run.py` should not process this ticket, even if it is a valid ticket to process. **note:** if this happens, and you fix the problem, simply uncheck the `Email Alerted` checkbox in the clickup ticket. Sibling tickets will not have the `Email Alerted` checkbox checked.

### run_queue

This script will grab and run any commands in the queue file. An example crontab to start this is here:
```
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