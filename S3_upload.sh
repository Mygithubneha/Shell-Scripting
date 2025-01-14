#!/bin/bash  

# Metadata  
# Author: Neha Avasekar  
# Date: 12/01/2025  
# Description: Script to upload Jenkins logs to S3, maintain metadata, handle lifecycle policies, and send email notifications.  
# Version: 4.0  

# Variables  
JENKINS_HOME="/var/lib/jenkins"  
S3_BUCKET="s3://log-storage-cost-optimization"  
LOG_FILE="/var/log/s3-log-upload.log"  
UPLOADED_LOGS_META="/var/log/uploaded_logs_meta.txt"  
ERROR_NOTIFICATION_EMAIL="navasekar@gmail.com"  

# Ensure metadata file exists  
if [ ! -f "$UPLOADED_LOGS_META" ]; then  
    touch "$UPLOADED_LOGS_META"  
fi  

# Check if Jenkins is installed  
if [ ! -d "$JENKINS_HOME" ]; then  
    echo "Jenkins is not installed. Please install Jenkins to proceed." | tee -a "$LOG_FILE"  
    exit 1  
fi  

# Check if AWS CLI is installed  
if ! command -v aws &>/dev/null; then  
    echo "AWS CLI is not installed. Please install it to proceed." | tee -a "$LOG_FILE"  
    exit 1  
fi  

# Apply lifecycle policy only if not already applied  
if ! aws s3api get-bucket-lifecycle-configuration --bucket "$(basename "$S3_BUCKET")" &>/dev/null; then  
    echo "Applying lifecycle management policy to S3 bucket..." | tee -a "$LOG_FILE"  
    aws s3api put-bucket-lifecycle-configuration --bucket "$(basename "$S3_BUCKET")" --lifecycle-configuration '{  
        "Rules": [  
            {  
                "ID": "TransitionToGlacier",  
                "Filter": {},  
                "Status": "Enabled",  
                "Transitions": [  
                    { "Days": 30, "StorageClass": "GLACIER" }  
                ],  
                "Expiration": { "Days": 365 }  
            }  
        ]  
    }'  
    echo "Lifecycle policy applied successfully." | tee -a "$LOG_FILE"  
else  
    echo "Lifecycle policy already applied. Skipping reapplication." | tee -a "$LOG_FILE"  
fi  

# Process logs  
uploaded_count=0  
skipped_count=0  

for job_dir in "$JENKINS_HOME/jobs/"*/; do  
    job_name=$(basename "$job_dir")  
    for build_dir in "$job_dir/builds/"*/; do  
        build_number=$(basename "$build_dir")  
        log_file="$build_dir/log"  

        if [ -f "$log_file" ]; then  
            log_identifier="$job_name-$build_number"  
            if grep -q "^$log_identifier$" "$UPLOADED_LOGS_META"; then  
                echo "Log $log_identifier already uploaded. Skipping." | tee -a "$LOG_FILE"  
                ((skipped_count++))  
            else  
                s3_path="$S3_BUCKET/$job_name/$build_number.log"  
                aws s3 cp "$log_file" "$s3_path" --only-show-errors  
                if [ $? -eq 0 ]; then  
                    echo "$log_identifier" >> "$UPLOADED_LOGS_META"  
                    echo "Uploaded: $log_identifier to $s3_path" | tee -a "$LOG_FILE"  
                    ((uploaded_count++))  
                fi  
            fi  
        fi  
    done  
done  

echo "Summary: $uploaded_count logs uploaded, $skipped_count skipped."  
