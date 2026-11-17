#!/bin/bash

# Fixed inactive file mover for Novastream
# Properly uploads inactive files to S3 using rclone

source /etc/s3-notify.conf

# Configuration
LOCAL_MEDIA="/novastream/local/cache/media"
S3_BUCKET="${S3_REMOTE:-s3remote:media-bucket}"
DAYS_INACTIVE=7  # Move files not accessed in 7 days
LOG_DIR="/var/log/novastream"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

echo "[$(date)] Starting inactive file migration (>${DAYS_INACTIVE} days)" | tee -a "${LOG_DIR}/move_inactive.log"

# Count inactive files
FILE_COUNT=$(find "$LOCAL_MEDIA" -type f -atime +${DAYS_INACTIVE} 2>/dev/null | wc -l)
echo "[$(date)] Found ${FILE_COUNT} inactive files" | tee -a "${LOG_DIR}/move_inactive.log"

if [[ $FILE_COUNT -eq 0 ]]; then
    echo "[$(date)] No inactive files to process" | tee -a "${LOG_DIR}/move_inactive.log"
    exit 0
fi

# Get initial disk usage
INITIAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')

# Process inactive files
MOVED=0
FAILED=0
TOTAL_SIZE=0

find "$LOCAL_MEDIA" -type f -atime +${DAYS_INACTIVE} 2>/dev/null | while read -r file; do
    if [[ -f "$file" ]]; then
        # Get file size for tracking
        FILE_SIZE=$(stat -c%s "$file" 2>/dev/null || echo 0)
        FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
        
        relative_path="${file#$LOCAL_MEDIA/}"
        target_dir="${S3_BUCKET}/$(dirname "$relative_path")"
        
        echo "[$(date)] Archiving: $(basename "$file") (${FILE_SIZE_MB}MB)" | tee -a "${LOG_DIR}/move_inactive.log"
        
        # Upload to S3 and remove local copy
        if rclone move "$file" "$target_dir/" --log-level ERROR 2>>"${LOG_DIR}/move_inactive_errors.log"; then
            ((MOVED++))
            TOTAL_SIZE=$((TOTAL_SIZE + FILE_SIZE_MB))
            echo "[$(date)] ✓ Archived: $(basename "$file")" | tee -a "${LOG_DIR}/move_inactive.log"
            
            # Send notification for large files
            if [[ $FILE_SIZE_MB -gt 1000 ]] && [[ -n "$DISCORD_WEBHOOK" ]]; then
                curl -H "Content-Type: application/json" -X POST \
                    -d "{\"embeds\":[{\"title\":\"📦 Large File Archived\",\"fields\":[{\"name\":\"File\",\"value\":\"$(basename "$file")\"},{\"name\":\"Size\",\"value\":\"${FILE_SIZE_MB}MB\"},{\"name\":\"Path\",\"value\":\"\`${relative_path}\`\"}],\"color\":3066993}]}" \
                    "$DISCORD_WEBHOOK" 2>/dev/null || true
            fi
        else
            ((FAILED++))
            echo "[$(date)] ✗ Failed: $(basename "$file")" | tee -a "${LOG_DIR}/move_inactive.log"
        fi
    fi
done

# Clean empty directories
echo "[$(date)] Cleaning empty directories" | tee -a "${LOG_DIR}/move_inactive.log"
find "$LOCAL_MEDIA" -type d -empty -delete 2>/dev/null

# Refresh rclone cache
echo "[$(date)] Refreshing rclone VFS cache" | tee -a "${LOG_DIR}/move_inactive.log"
rclone rc vfs/refresh recursive=true --fast-list 2>/dev/null || true

# Get final disk usage
FINAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
FREED=$((INITIAL_USAGE - FINAL_USAGE))

echo "[$(date)] Migration complete. Moved: ${MOVED}, Failed: ${FAILED}, Total: ${TOTAL_SIZE}MB" | tee -a "${LOG_DIR}/move_inactive.log"
echo "[$(date)] Disk usage: ${INITIAL_USAGE}% -> ${FINAL_USAGE}% (freed ${FREED}%)" | tee -a "${LOG_DIR}/move_inactive.log"

# Send summary notification
if [[ -n "$DISCORD_WEBHOOK" ]] && [[ $MOVED -gt 0 ]]; then
    curl -H "Content-Type: application/json" -X POST \
        -d "{\"content\":\"📦 **Inactive File Archive Complete**\\nFiles archived: ${MOVED}\\nFailed: ${FAILED}\\nTotal size: ${TOTAL_SIZE}MB\\nDisk freed: ${FREED}%\"}" \
        "$DISCORD_WEBHOOK" 2>/dev/null || true
fi