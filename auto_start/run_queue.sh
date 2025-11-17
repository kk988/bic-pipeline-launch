#! /bin/bash

set -e

#export LSF_LIBDIR=/admin/lsfjuno/lsf/10.1/linux3.10-glibc2.17-x86_64/lib
#export LSF_SERVERDIR=/admin/lsfjuno/lsf/10.1/linux3.10-glibc2.17-x86_64/etc
#export LSF_ENVDIR=/admin/lsfjuno/lsf/conf
#export PATH="$PATH:/admin/lsfjuno/lsf/10.1/linux3.10-glibc2.17-x86_64/bin"

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

