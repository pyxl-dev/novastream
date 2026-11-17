#!/bin/bash

# Fixed space check script for Novastream
# This properly uploads files to S3 instead of trying to move them locally

source /etc/s3-notify.conf

# Configuration
LOCAL_MEDIA="/novastream/local/cache/media"
S3_BUCKET="${S3_REMOTE:-s3remote:media-bucket}"
THRESHOLD=70
MIN_AGE_MINUTES=60  # Files older than 1 hour
LOG_DIR="/var/log/novastream"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Get current disk usage
LOCAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')

echo "[$(date)] Disk usage check: ${LOCAL_USAGE}%" | tee -a "${LOG_DIR}/space_cleanup.log"

if [[ $LOCAL_USAGE -ge $THRESHOLD ]]; then
    echo "[$(date)] Space critical (${LOCAL_USAGE}%), starting S3 upload" | tee -a "${LOG_DIR}/space_cleanup.log"
    
    # Count files to upload
    FILE_COUNT=$(find "$LOCAL_MEDIA" -type f -mmin +${MIN_AGE_MINUTES} 2>/dev/null | wc -l)
    echo "[$(date)] Found ${FILE_COUNT} files older than ${MIN_AGE_MINUTES} minutes" | tee -a "${LOG_DIR}/space_cleanup.log"
    
    # Upload old files to S3 and remove local copies
    UPLOADED=0
    FAILED=0
    
    find "$LOCAL_MEDIA" -type f -mmin +${MIN_AGE_MINUTES} 2>/dev/null | while read -r file; do
        if [[ -f "$file" ]]; then
            relative_path="${file#$LOCAL_MEDIA/}"
            target_dir="${S3_BUCKET}/$(dirname "$relative_path")"
            
            echo "[$(date)] Uploading: $file -> $target_dir" | tee -a "${LOG_DIR}/space_cleanup.log"
            
            # Upload to S3 using rclone move (uploads and deletes local)
            if rclone move "$file" "$target_dir/" --log-level ERROR 2>>"${LOG_DIR}/space_cleanup_errors.log"; then
                ((UPLOADED++))
                echo "[$(date)] ✓ Uploaded: $(basename "$file")" | tee -a "${LOG_DIR}/space_cleanup.log"
            else
                ((FAILED++))
                echo "[$(date)] ✗ Failed: $(basename "$file")" | tee -a "${LOG_DIR}/space_cleanup.log"
            fi
        fi
    done
    
    # Clear rclone VFS cache to reflect changes
    echo "[$(date)] Refreshing rclone VFS cache" | tee -a "${LOG_DIR}/space_cleanup.log"
    rclone rc vfs/refresh recursive=true --fast-list 2>/dev/null || true
    
    # Clean empty directories
    find "$LOCAL_MEDIA" -type d -empty -delete 2>/dev/null
    
    # Get new disk usage
    NEW_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
    FREED=$((LOCAL_USAGE - NEW_USAGE))
    
    echo "[$(date)] Cleanup complete. Before: ${LOCAL_USAGE}%, After: ${NEW_USAGE}%, Freed: ${FREED}%" | tee -a "${LOG_DIR}/space_cleanup.log"
    
    # Send notification if webhook is configured
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        curl -H "Content-Type: application/json" -X POST \
            -d "{\"content\":\"✅ **S3 Upload Complete**\\nFiles processed: ${FILE_COUNT}\\nSpace before: ${LOCAL_USAGE}%\\nSpace after: ${NEW_USAGE}%\\nFreed: ${FREED}%\"}" \
            "$DISCORD_WEBHOOK" 2>/dev/null || true
    fi
else
    echo "[$(date)] Disk usage OK (${LOCAL_USAGE}%)" | tee -a "${LOG_DIR}/space_cleanup.log"
fi