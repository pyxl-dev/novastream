#!/bin/bash

# Monitor the emergency upload progress

echo "================================"
echo "UPLOAD PROGRESS MONITOR"
echo "================================"
echo ""

# Check if rclone process is running
if pgrep -f "rclone move" > /dev/null; then
    echo "✅ Upload is RUNNING"
    echo ""
    
    # Get latest progress
    echo "Current Progress:"
    tail -1 ./logs/upload_output.log | grep -oE '[0-9.]+ [GMK]iB / [0-9.]+ [GMK]iB.*ETA.*'
    echo ""
    
    # Show disk usage
    echo "Disk Usage:"
    df -h / | grep -E "Filesystem|/dev/vda1"
    echo ""
    
    # Show recent uploads
    echo "Recent Uploads:"
    tail -5 ./logs/emergency_upload.log | grep "INFO"
    echo ""
    
    # Count files in S3
    echo "Checking S3 bucket..."
    S3_COUNT=$(rclone ls ${S3_REMOTE:-s3remote:media-bucket} 2>/dev/null | wc -l)
    echo "Files in S3: $S3_COUNT"
    
else
    echo "❌ Upload is NOT running"
    echo ""
    
    # Check if it completed
    if grep -q "UPLOAD COMPLETE" ./logs/upload_output.log 2>/dev/null; then
        echo "✅ Upload COMPLETED"
        tail -10 ./logs/upload_output.log | grep -E "COMPLETE|freed|usage"
    else
        echo "⚠️  Upload may have failed or not started"
        echo "Check: ./logs/upload_output.log"
    fi
fi

echo ""
echo "================================"
echo "For full logs:"
echo "  tail -f ./logs/upload_output.log"
echo "================================"