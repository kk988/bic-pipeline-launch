## Syncing fastq
This will help transfer the fastqs from IGO's delivery directory to our working directories for analysis.

## Setup
### Queue file
This script requires a queue file to be present somewhere. It can be empty (and will be most of the time). When you want to transfer a set of files, you will write the full path to the `_sample_mapping.txt` file that contains the fastq we want to transfer into the queue file. 

#### Create queue file
To create the queue file, just touch a file, ex: `touch /data1/core001/CACHE/queue_list.txt`. 

#### Add to queue file
To add to the queue file, add the full path to the mapping file for the fastqs you want to sync. Ex: `echo "/data/core001/work/rnaseq/Proj_1234/Proj_1234_sample_mapping.txt" >> /data1/core001/CACHE/queue_list.txt` 

### sync_fastq.sh setup
There are a few things in the sync_fastq.sh that should be customized before you start using the script. Most of the time nothing will have to change, but I just wanted to mention these. 
``` 
path_to_rsync="/data1/core001/CACHE/igo/"
rsync_group="grp_hpc_core001"
rsync_user=$(whoami)
host="iris"
```
These are at the beginning of the script, and can be changed.
*ALSO* - There is a variable called `iris_dir` which uses `sed` to change the fastq path from a juno based path to an iris based path (from `/igo/delivery` to `/ifs/datadelivery/igo_core`). If these paths change, you may need to update this.

### crontab creation
I run this via crontab. My crontab looks as such:
``` 
MAILTO="kazmierk@mskcc.org"

54 * * * * /path/to/sync_fastq.sh /path/to/queue_list.txt
```

