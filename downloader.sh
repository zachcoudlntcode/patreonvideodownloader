#!/bin/bash
# filepath: c:\Users\zachm\OneDrive\Documents\Python Projects\Patreon Video Downloader\patreonvideodownloader\patreonvideodownloader\downloader.sh

set -e

# Debug info
echo "DEBUG: Environment variables received:"
echo "DEBUG: CREATOR_URL=${CREATOR_URL}"
echo "DEBUG: MAX_POSTS=${MAX_POSTS:-20}"
echo "DEBUG: CHECK_INTERVAL=${CHECK_INTERVAL:-3600}"
echo "DEBUG: ACCESS_TOKEN=${ACCESS_TOKEN:0:6}..."
echo "DEBUG: REFRESH_TOKEN=${REFRESH_TOKEN:0:6}..."

# Ensure directories exist
mkdir -p /data/config
mkdir -p /data/downloads

# Create yt-dlp config with Patreon tokens
if [[ -n "$ACCESS_TOKEN" && -n "$REFRESH_TOKEN" ]]; then
    echo "Using provided access and refresh tokens from environment variables"
    cat > /data/config/yt-dlp.conf << EOF
--netrc-cmd "echo machine patreon.com login oauth password ${ACCESS_TOKEN}"
--extractor-args "patreon:access_token=${ACCESS_TOKEN};refresh_token=${REFRESH_TOKEN}"
EOF
else
    echo "ERROR: No ACCESS_TOKEN or REFRESH_TOKEN provided"
    echo "Please set the ACCESS_TOKEN and REFRESH_TOKEN environment variables"
    exit 1
fi

echo "Patreon Downloader starting..."
echo "Monitoring creator: ${CREATOR_URL}"

# Function to check and download new videos
check_for_videos() {
    echo "----------------------------------------"
    echo "Starting check at $(date)"
    echo "Checking ${CREATOR_URL}"
    
    # Create a temporary download archive if it doesn't exist
    if [ ! -f /data/config/download_archive.txt ]; then
        touch /data/config/download_archive.txt
    fi

    # Run yt-dlp with proper authentication and options
    yt-dlp --config-location /data/config/yt-dlp.conf \
        --download-archive /data/config/download_archive.txt \
        --write-info-json \
        --playlist-items 1-${MAX_POSTS:-20} \
        -o "/data/downloads/%(creator)s/%(title)s [%(id)s].%(ext)s" \
        --verbose \
        ${CREATOR_URL} || true
        
    # Count how many entries we checked and how many new ones were downloaded
    CHECKED=$(grep -c "Patreon" /tmp/yt-dlp.log 2>/dev/null || echo "0")
    DOWNLOADED=$(grep -c "Destination" /tmp/yt-dlp.log 2>/dev/null || echo "0")
    
    echo "Check completed: ${CHECKED} posts checked, ${DOWNLOADED} new downloads"
}

# Main loop
while true; do
    # Create a log file for this run
    rm -f /tmp/yt-dlp.log
    check_for_videos > /tmp/yt-dlp.log 2>&1
    cat /tmp/yt-dlp.log
    
    echo "Waiting ${CHECK_INTERVAL:-3600} seconds until next check..."
    sleep ${CHECK_INTERVAL:-3600}
done