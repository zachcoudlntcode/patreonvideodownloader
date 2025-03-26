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
    
    # Create .netrc file for yt-dlp authentication
    cat > /data/config/.netrc << EOF
machine patreon.com
login oauth
password ${ACCESS_TOKEN}
EOF
    chmod 600 /data/config/.netrc
    
    # Create extractor args config
    cat > /data/config/extractor_args.conf << EOF
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
    yt-dlp --netrc-file /data/config/.netrc \
        --config-location /data/config/extractor_args.conf \
        --download-archive /data/config/download_archive.txt \
        --write-info-json \
        --playlist-items 1-${MAX_POSTS:-20} \
        -o "/data/downloads/%(creator)s/%(title)s [%(id)s].%(ext)s" \
        --verbose \
        ${CREATOR_URL}
        
    # Count how many new downloads
    DOWNLOADED=$?
    if [ $DOWNLOADED -eq 0 ]; then
        echo "Check completed successfully"
    else
        echo "Check completed with errors"
    fi
}

# Main loop
while true; do
    check_for_videos
    echo "Waiting ${CHECK_INTERVAL:-3600} seconds until next check..."
    sleep ${CHECK_INTERVAL:-3600}
done