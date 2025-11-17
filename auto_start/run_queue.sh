#! /bin/bash

set -e

# This script will be used to execute the run scripts for pipeline runs
# a pipeline command will be written to a "queue" file
# and this script will just, pull first first line and execute it.

queue_to_read=$1

# check if the queue file exists
if [ ! -f $queue_to_read ]; then
    echo "Queue file $queue_to_read does not exist."
    exit 1
fi

cmd=$(head -n 1 $queue_to_read)

# check if the command is empty
# if so silently exit
if [ -z "$cmd" ]; then
    exit 1
fi

# execute command 
eval $cmd

echo "Ran command ${cmd}"

# remove line so it doesn't stick around
sed -i '1d' $queue_to_read

