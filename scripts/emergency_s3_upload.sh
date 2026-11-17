#!/bin/bash

# Emergency S3 Upload Script for Novastream
# Use this to immediately free disk space by uploading all media to S3

set -euo pipefail

# Configuration
LOCAL_MEDIA="/novastream/local/cache/media"
S3_BUCKET="${S3_REMOTE:-s3remote:media-bucket}"
LOG_FILE="./logs/emergency_upload.log"
PARALLEL_TRANSFERS=4
DRY_RUN="${DRY_RUN:-false}"  # DRY_RUN=true pour tester sans rien déplacer

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to print colored output
print_status() {
    echo -e "${2}${1}${NC}" | tee -a "$LOG_FILE"
}

# Check if running as appropriate user
if [[ $EUID -eq 0 ]]; then
   print_status "Warning: Running as root. Consider running as the media user." "$YELLOW"
fi

print_status "=== EMERGENCY S3 UPLOAD STARTING ===" "$GREEN"
print_status "Time: $(date)" "$GREEN"
print_status "Local path: $LOCAL_MEDIA" "$GREEN"
print_status "S3 bucket: $S3_BUCKET" "$GREEN"
print_status "Dry run: $DRY_RUN" "$GREEN"

# Check if source directory exists
if [[ ! -d "$LOCAL_MEDIA" ]]; then
    print_status "Error: Source directory $LOCAL_MEDIA does not exist!" "$RED"
    exit 1
fi

# Get initial disk usage
INITIAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
INITIAL_SIZE=$(du -sh "$LOCAL_MEDIA" 2>/dev/null | cut -f1)
print_status "Initial disk usage: ${INITIAL_USAGE}%" "$YELLOW"
print_status "Media folder size: ${INITIAL_SIZE}" "$YELLOW"

# Count files to upload
print_status "Counting files..." "$YELLOW"
TOTAL_FILES=$(find "$LOCAL_MEDIA" -type f 2>/dev/null | wc -l)
print_status "Total files to process: $TOTAL_FILES" "$YELLOW"

if [[ $TOTAL_FILES -eq 0 ]]; then
    print_status "No files to upload. Exiting." "$GREEN"
    exit 0
fi

# Ask for confirmation (skipped for non-interactive run)
if [[ "$DRY_RUN" == "false" ]] && [[ -t 0 ]]; then
    echo -e "${YELLOW}This will upload and DELETE $TOTAL_FILES local files after successful upload.${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
    read -r
else
    echo -e "${YELLOW}Non-interactive mode: proceeding with upload of $TOTAL_FILES files${NC}"
fi

# Prepare rclone command
RCLONE_CMD="rclone"
if [[ "$DRY_RUN" == "true" ]]; then
    RCLONE_CMD="$RCLONE_CMD --dry-run"
fi

# Start upload with progress
print_status "Starting upload to S3..." "$GREEN"
print_status "This may take a while for large libraries..." "$YELLOW"

# Upload with detailed progress
$RCLONE_CMD move "$LOCAL_MEDIA" "$S3_BUCKET" \
    --transfers "$PARALLEL_TRANSFERS" \
    --checkers 8 \
    --log-level INFO \
    --log-file "$LOG_FILE" \
    --progress \
    --stats 10s \
    --stats-one-line \
    --delete-empty-src-dirs

# Check if upload was successful
if [[ $? -eq 0 ]]; then
    print_status "Upload completed successfully!" "$GREEN"
else
    print_status "Upload encountered errors. Check log file: $LOG_FILE" "$RED"
    exit 1
fi

# Refresh rclone mount cache
print_status "Refreshing rclone mount cache..." "$YELLOW"
rclone rc vfs/refresh recursive=true --fast-list 2>/dev/null || true
rclone rc vfs/forget recursive=true --fast-list 2>/dev/null || true

# Get final disk usage
FINAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
FINAL_SIZE=$(du -sh "$LOCAL_MEDIA" 2>/dev/null | cut -f1 || echo "0")
FREED=$((INITIAL_USAGE - FINAL_USAGE))

print_status "=== UPLOAD COMPLETE ===" "$GREEN"
print_status "Initial disk usage: ${INITIAL_USAGE}%" "$GREEN"
print_status "Final disk usage: ${FINAL_USAGE}%" "$GREEN"
print_status "Space freed: ${FREED}%" "$GREEN"
print_status "Media folder: ${INITIAL_SIZE} -> ${FINAL_SIZE}" "$GREEN"

# Send notification if webhook exists
if [[ -f /etc/s3-notify.conf ]]; then
    source /etc/s3-notify.conf
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        curl -H "Content-Type: application/json" -X POST \
            -d "{\"content\":\"🚨 **Emergency S3 Upload Complete**\\nFiles uploaded: ${TOTAL_FILES}\\nDisk freed: ${FREED}%\\nDisk usage: ${FINAL_USAGE}%\"}" \
            "$DISCORD_WEBHOOK" 2>/dev/null || true
    fi
fi

print_status "Log file: $LOG_FILE" "$YELLOW"
print_status "Done!" "$GREEN"