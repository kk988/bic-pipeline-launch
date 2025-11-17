#!/bin/bash

# if there are not 4 arguments, print usage and exit
if [ $# -ne 4 ]; then
    echo "Usage: email_delivery_template.sh <project_id> <run_number> <investigator_name> <emails_to_send>"
    echo "project_id: project id"
    echo "run_number: run number"
    echo "investigator_name: investigator name"
    echo "emails_to_send: emails to send"
    exit 1
fi

PID=$1
RUN_NUM=$2
INV_NAME=$3
EMAILS_TO_SEND=$4

INV_FIRST_NAME=${INV_NAME#*, }

SENDER_NAME="Bioinformatics Core"
SENDER_EMAIL="bicrequest@mskcc.org"
DELIVERY_URL="https://bicdelivery.mskcc.org/project/${PID}/rnaseq/${RUN_NUM}/project_main"
INFO_URL="https://bic.mskcc.org/bic/rnaseq-delivery-information/"
EMAIL_US_URL="mailto:bicrequest@mskcc.org"
SURVEY_URL="http://bic.mskcc.org/bic/rnaseq-analysis-feedback"

RECIPIENT="kazmierk@mskcc.org"
SUBJECT="Proj_${PID} results"
HTML_BODY="<html><body><p>SEND EMAIL TO: ${EMAILS_TO_SEND}</p> \
<p>This is an <b>HTML email</b> sent using a shell script.</p> \
<p>Hi ${INV_FIRST_NAME},</p> \
<p>The files from the RNA-Seq analysis are ready for <a href='${DELIVERY_URL}'>download</a>. Please log in using your MSKCC username and password. \
You must be within the MSKCC network in order to access the BIC delivery website.</p> \
<p>More information about the analysis can be found <a href='${INFO_URL}'>here</a>, including details about the pipeline and the output files. \
You can also find information there about requesting additional custom analyses and figures for your project.</p> \
<p>The standard pipeline service includes the following: BAM files will be stored for six months, \
after which they will be deleted from the server. Other results files will be stored as long as space permits, \
which in the past has typically been several years. We strongly recommend making a personal backup copy of all files. \
Please <a href='${EMAIL_US_URL}'>contact us</a> if you require assistance copying your data or would like to discuss long-term storage options.</p> \
<p>We welcome your feedback. Please complete <a href='${SURVEY_URL}'>this short survey</a> to help us improve our services.</p> \
<p>Thanks,</p> \
<p>Bioinformatics Core</p> \
</body></html>"

#echo -e "$HTML_BODY" | mailx -a 'Content-Type: text/html' -s "$SUBJECT" "$RECIPIENT"

(
echo "From: $SENDER_NAME <$SENDER_EMAIL>"
echo "To: $RECIPIENT"
echo "Subject: $SUBJECT"
echo "Content-Type: text/html"
echo ""
echo "$HTML_BODY"
) | sendmail -t