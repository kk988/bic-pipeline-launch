#! /bin/bash
set -e

# This script needs to do some finalization of the pipeline. Things it will do:
# 1. Move project files to the <outdir>/project_files directory.
# 2. Run bicdelivery_summary script.
# 3. Rsync the results to the rsync directory

script_dir=$(dirname "$(realpath "$0")")

# if there is not 4 arguments, print usage and exit
if [ $# -ne 7 ]; then
    echo "Usage: rsync_summary_finalize.sh <rundir> <outdir> <rsync_dir> <panda_simg> <pfg_simg> <delivery_dir> <cluster>"
    echo "run_dir: directory where the pipeline was run (should have project files)"
    echo "out_dir: outdir provided to the pipeline"
    echo "rsync_dir: directory to rsync the results to"
    echo "panda_simg: path to the panda singularity image"
    echo "pfg_simg: path to the pfg singularity image"
    echo "delivery_dir: directory to rsync the results to for delivery"
    echo "cluster: cluster that this script is running on"
    exit 1
fi

# grab rundir output, rsync dirs from command line
run_dir=$1
out_dir=$2
rsync_dir=$3
panda_simg=$4
pfg_simg=$5
delivery_dir=$6
cluster=$7

# if outdir is not a full path, add it to run_dir.
if [[ $out_dir != /* ]]; then
    out_dir=$run_dir/$out_dir
fi

#
# softlink gsea report index.html to outdir
#
curr_pwd=$(pwd)
# if gsea report directory exists, create a softlink to the index.html file
if [ -d ${out_dir}/star_htseq/differentialExpression_gene/report/gsea ]; then
    echo "GSEA report directory exists, creating softlink to index.html"
    cd ${out_dir}/star_htseq/differentialExpression_gene/report/gsea;
    # if *index.html files are already softlinked, delete the softlink and redo it
    if ls *.index.html 1>/dev/null 2>&1; then
        rm *.index.html
    fi
    ln -s */*/*index.html .
    cd $curr_pwd
fi

#
# Move project to project_files directory
#
mkdir -p $out_dir/project_files
cp $run_dir/*sample_mapping.txt $run_dir/*request.txt $run_dir/input.csv $out_dir/project_files/

# Check if files matching the pattern exist and copy them if they do
if ls $run_dir/*sample_key*txt 1>/dev/null 2>&1; then
    cp $run_dir/*sample_key*txt $out_dir/project_files/
fi

if ls $run_dir/*sample_comparison*txt 1>/dev/null 2>&1; then
    cp $run_dir/*sample_comparison*txt $out_dir/project_files/
fi

if ls $run_dir/contrasts*csv 1>/dev/null 2>&1; then
    cp $run_dir/contrasts*csv $out_dir/project_files/
fi

#
# Run bicdelivery_summary script
#
singularity exec -B ${script_dir} -B ${run_dir} $panda_simg python ${script_dir}/bicdelivery_summary.py $out_dir

#
# Rsync the results to the rsync directory
#

echo "rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir"
rsync -avzP --exclude-from=${script_dir}/rsync_excludes.txt $run_dir $rsync_dir

#
# final checks - store stderr in variable
#
echo "Running post-pipeline checks..."
echo "python3 ${script_dir}/postpipeline_checks.py $run_dir 2>&1"
this_stderr=$(python3 ${script_dir}/postpipeline_checks.py $run_dir 2>&1)

#
# rsync to delivery directory
#
pi=$(grep ^PI: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
inv=$(grep ^Investigator: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
inv_name=$(grep ^Investigator_Name: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
proj_id=$(grep ^ProjectID: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
run_num="r_$(grep ^RunNumber $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " " | xargs printf "%03d" )"
build=$(grep ^Build: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
if [ -z "$pi" ] || [ -z "$inv" ]; then
    printf "No PI or Investigator found in request file, not delivering project!\n"
    exit 1
fi
del_path=${delivery_dir}/${pi}/${inv}/${proj_id}/

delivery_user="none"
delivery_host="none"
# if delivery_dir contains an @ in it, don't mkdir -p, just rsync
if [[ $delivery_dir == *"@"* ]]; then
    delivery_user=$(echo $delivery_dir | cut -d"@" -f1)
    delivery_host=$(echo $delivery_dir | cut -d"@" -f2 | cut -d":" -f1)
    echo "Delivery directory contains an @, have to create files differently"
    del_path_no_server=${del_path#*:}
    create_dirs="ssh ${delivery_user}@${delivery_host} 'umask 002 && mkdir -m 775 -p ${del_path_no_server}'"
    eval $create_dirs
else
    mkdir -m 775 -p $del_path
fi

echo "rsync -avz --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r --exclude-from=${script_dir}/rsync_excludes.txt $out_dir $del_path"
rsync -avz --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r --exclude-from=${script_dir}/rsync_excludes.txt $out_dir $del_path

#
# ticket_update
#
# if grab lines from stderr that start with ERROR, add to comment in ticket
# grab pipeline version for both rnaseq and diff
# close those tickets.
comments=""
ticket_id=""
diff_ver=""
err_lines=$(echo "$this_stderr" | grep ^ERROR || true)

#save comments if there are error lines
if [ ! -z "$err_lines" ]; then
    comments="Post-pipeline checks found some issues:\n$err_lines"
fi

## PEROFRM DELIVERY
# This is going to be a crazy command because I have to run it in one big line on delivery host.
del_path_no_server="${del_path#*:}"

cmd_for_delivery="ssh ${delivery_user}@${delivery_host} 'export MODULEPATH=/compute/juno/bic/ROOT/opt/modulefiles:$MODULEPATH \
&& . /usr/share/Modules/init/bash && module load singularity/3.7.1 && cd $del_path_no_server \
&& cp ${del_path_no_server}/${run_num}/project_files/Proj*request.txt . \
&& singularity exec --bind /juno/bic --bind /ifs /juno/opt/common/bic/internal/project_file_generation/pfg.simg python3 /authorization_db/init_project_permissions.py --project_path $del_path_no_server --assembly $build \
&& rm Proj*request.txt'"

echo "Running delivery command: $cmd_for_delivery"
eval $cmd_for_delivery

# grab ticket id from run_dir/clickup_task_id.txt if it exists
if [ -f $run_dir/clickup_task_id.txt ]; then
    ticket_id=$(cat $run_dir/clickup_task_id.txt)
fi

rnaseq_ver=$(grep nf-core/rnaseq $out_dir/pipeline_info/*.yml | cut -f2 -d":" | tr -d " ")
if [ -d $out_dir/star_htseq/differentialExpression_gene ]; then
    diff_ver=$(grep nf-core/differentialabundance $out_dir/star_htseq/differentialExpression_gene/pipeline_info/*.yml | cut -f2 -d":" | tr -d " ")
fi

close_pipeline_cmd="python ${script_dir}/close_pipeline_subtasks.py --ticket_id $ticket_id --rnaseq_ver $rnaseq_ver --rsync_dir $rsync_dir --del_path ${del_path_no_server}/${run_num}"

echo -e "RNA-seq pipeline version: $rnaseq_ver"
if [ ! -z "$diff_ver" ]; then
    echo -e "Diff pipeline version: $diff_ver"
    close_pipeline_cmd="$close_pipeline_cmd --diff_ver $diff_ver"
fi
if [ ! -z "$comments" ]; then
    echo -e "Comments for ticket:\n$comments"
    close_pipeline_cmd="$close_pipeline_cmd --comments \"$comments\""
fi

if [ ! -z "$ticket_id" ]; then
    echo "Updating ticket: $ticket_id"
    script_parent_dir=$(dirname ${script_dir})
    echo "Running singularity exec -B ${script_parent_dir} -B ${run_dir} $pfg_simg $close_pipeline_cmd"
    singularity exec -B ${script_parent_dir} -B ${run_dir} $pfg_simg $close_pipeline_cmd
fi


if [ $cluster == "iris" ]; then
    echo "Removing fastq files from CACHE directory"
    rm -r /data1/core001/CACHE/igo/${proj_id}
fi

#
# email delivery
#
eml1=$(grep ^DeliverTo_Email: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
eml2=$(grep ^PI_E-mail: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")
eml3=$(grep ^Investigator_E-mail: $out_dir/project_files/*request.txt | cut -f2 -d":" | tr -d " ")

all_emails=$(printf '%s\n%s\n%s\n' "$eml1" "$eml2" "$eml3" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -u)
unique_emails=$(echo "$all_emails" | tr '\n' ',' | sed 's/,$//')

email_delivery_cmd="bash ${script_dir}/email_delivery_template.sh $proj_id $run_num '$inv_name' $unique_emails"
echo "Running email delivery command: $email_delivery_cmd"
eval $email_delivery_cmd
