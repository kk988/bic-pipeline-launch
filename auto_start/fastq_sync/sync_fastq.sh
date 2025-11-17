# Here we will rsync the fastq files from the delivery directory to the local file system
# This script will be run as a cron job on lilac

# Script will read a static file one line at a time
#     This line will be the path to the mapping file
# Script will rsync fastq files found in the mapping file
# Script will create an updated mapping file with the new paths

path_to_rsync="/data1/core001/CACHE/igo/"
rsync_group="grp_hpc_core001"
rsync_user=$(whoami)
host="iris"

fq_queue=$1

# Check if the file exists
if [ ! -f $fq_queue ]; then
    echo "File does not exist"
    exit 1
fi

# Gather the first line
mapping=$(head -n 1 $fq_queue)

# Exit if no line was captured
if [ -z $mapping ]; then
    exit 0
fi

echo "Mapping file: $mapping"

# remove line so it doesn't stick around
sed -i '1d' $fq_queue

# Check if the file exists
if [ ! -f $mapping ]; then
    echo "Mapping file does not exist"
    exit 1
fi

# Check if new mapping file was already created
# If so exit.
if [ -f ${mapping}"_${host}.txt" ]; then
    echo "New mapping file already exists. Please delete and re-add $mapping to the queue."
    exit 1
fi

# Get the unique directories from mapping file
orig_dir=$(cut -f4 $mapping | sort | uniq)

# Set up rsync dir
map_fn=$(basename $mapping)
project=${map_fn%_sample_mapping.txt}

# Check if project directory already exists
if [ -d $path_to_rsync/$project ]; then
    echo "Project directory already exists"
    exit 1
fi

# rsync each directory to the project directory
for dir in $orig_dir; do

	iris_dir=$(echo $dir | sed 's|/igo/delivery/|/ifs/datadelivery/igo_core/|g')
	# This means we can't use the rsync for external projects.
    long_proj=$(basename $(dirname $dir))
    run_path=$(basename $(dirname $(dirname $dir)))
    mkdir -p $path_to_rsync/$project/$run_path/$long_proj
    echo "Rsyncing $iris_dir"
    rsync -avzP --chown=${rsync_user}:${rsync_group} $iris_dir $path_to_rsync/$project/$run_path/$long_proj
done

# make a new mapping file
old_path="/ifs/datadelivery/igo_core/FASTQ"
sed "s|${old_path}|${path_to_rsync}/${project}|g" $mapping > ${mapping}"_${host}.txt"

chmod 664 ${mapping}"_${host}.txt"

echo "DONE"
exit 0
