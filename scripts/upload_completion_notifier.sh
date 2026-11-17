#!/bin/bash

# Script to monitor upload completion and send Discord notification

DISCORD_WEBHOOK="${DISCORD_WEBHOOK:?Definir DISCORD_WEBHOOK}"
USER_ID="${DISCORD_USER_ID:-}"
LOG_FILE="./logs/upload_output.log"
UPLOAD_LOG="./logs/emergency_upload.log"

echo "Starting upload completion monitor..."

# Wait for upload to complete
while pgrep -f "rclone move" > /dev/null; do
    sleep 30
done

echo "Upload process completed. Gathering statistics..."

# Get final statistics
FINAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
FINAL_SIZE=$(du -sh /novastream/local/cache/media 2>/dev/null | cut -f1 || echo "0")
S3_COUNT=$(rclone ls ${S3_REMOTE:-s3remote:media-bucket} 2>/dev/null | wc -l)

# Parse initial values from log
INITIAL_USAGE=$(grep "Initial disk usage:" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+' || echo "92")
INITIAL_SIZE=$(grep "Media folder size:" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+G' || echo "76G")

# Calculate freed space
FREED=$((INITIAL_USAGE - FINAL_USAGE))

# Check if upload was successful
if grep -q "Upload completed successfully" "$LOG_FILE" 2>/dev/null || [ $FREED -gt 0 ]; then
    STATUS="✅ SUCCESS"
    COLOR="3066993"
else
    STATUS="⚠️ COMPLETED WITH ISSUES"
    COLOR="15105570"
fi

# Send Discord notification
curl -H "Content-Type: application/json" -X POST \
    -d "{
        \"content\": \"<@${USER_ID}>\",
        \"embeds\": [{
            \"title\": \"🚀 Novastream S3 Upload Complete\",
            \"description\": \"The emergency S3 upload has finished.\",
            \"color\": ${COLOR},
            \"fields\": [
                {
                    \"name\": \"Status\",
                    \"value\": \"${STATUS}\",
                    \"inline\": true
                },
                {
                    \"name\": \"Files in S3\",
                    \"value\": \"${S3_COUNT}\",
                    \"inline\": true
                },
                {
                    \"name\": \"Space Freed\",
                    \"value\": \"${FREED}%\",
                    \"inline\": true
                },
                {
                    \"name\": \"Disk Usage Before\",
                    \"value\": \"${INITIAL_USAGE}% (${INITIAL_SIZE})\",
                    \"inline\": true
                },
                {
                    \"name\": \"Disk Usage After\",
                    \"value\": \"${FINAL_USAGE}% (${FINAL_SIZE})\",
                    \"inline\": true
                },
                {
                    \"name\": \"Time\",
                    \"value\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
                    \"inline\": true
                }
            ],
            \"footer\": {
                \"text\": \"Novastream Media Server\"
            },
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
        }]
    }" "$DISCORD_WEBHOOK"

echo "Discord notification sent!"
echo "Final statistics:"
echo "- Status: $STATUS"
echo "- Disk freed: ${FREED}%"
echo "- Current usage: ${FINAL_USAGE}%"
echo "- Files in S3: ${S3_COUNT}"