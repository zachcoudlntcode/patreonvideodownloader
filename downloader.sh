#!/bin/bash

CONFIG_DIR="/data/config"
DOWNLOAD_DIR="/data/downloads"
COOKIES_FILE="${CONFIG_DIR}/cookies.txt"
PROCESSED_FILE="${CONFIG_DIR}/processed_posts.txt"
MAX_POSTS=${MAX_POSTS:-20}
CHECK_INTERVAL=${CHECK_INTERVAL:-3600}
CREATOR_URL=${CREATOR_URL:-""}

# Debug information
echo "DEBUG: Environment variables received:"
echo "DEBUG: CREATOR_URL=$CREATOR_URL"
echo "DEBUG: MAX_POSTS=$MAX_POSTS"
echo "DEBUG: CHECK_INTERVAL=$CHECK_INTERVAL"

# Setup
mkdir -p "${CONFIG_DIR}" "${DOWNLOAD_DIR}"
touch "${PROCESSED_FILE}"

if [ ! -f "${COOKIES_FILE}" ]; then
  echo "Warning: cookies.txt not found in ${CONFIG_DIR}"
  echo "You may need to provide cookies to access patron-only content"
fi

echo "Patreon Downloader starting..."
echo "Monitoring creator: ${CREATOR_URL}"

# Extract ID function to make it cleaner
extract_id() {
  local json="$1"
  echo "$json" | grep -o '"id":[[:space:]]*"[0-9]*"' | grep -o '[0-9]*'
}

# Extract title function
extract_title() {
  local json="$1"
  echo "$json" | grep -o '"title":[[:space:]]*"[^"]*"' | sed 's/.*"title":[[:space:]]*"\([^"]*\)".*/\1/'
}

# Check if post is already processed
is_processed() {
  local id="$1"
  grep -q "^${id}$" "${PROCESSED_FILE}"
}

# Mark post as processed
mark_processed() {
  local id="$1"
  echo "${id}" >> "${PROCESSED_FILE}"
}

# Main loop
while true; do
  echo "----------------------------------------"
  echo "Starting check at $(date)"
  
  if [ -z "${CREATOR_URL}" ]; then
    echo "Error: CREATOR_URL environment variable not set"
    sleep 60
    continue
  fi
  
  # Create direct URL to the creator's posts
  POSTS_URL="${CREATOR_URL}"
  
  # Use yt-dlp to list available videos without downloading
  echo "Checking ${POSTS_URL}"
  
  # Get recent posts
  POSTS_LIST=$(mktemp)
  yt-dlp --dump-json --playlist-items "1-${MAX_POSTS}" \
    --cookies "${COOKIES_FILE}" "${POSTS_URL}" 2>/dev/null > "${POSTS_LIST}" || true
  
  # Process each post
  POSTS_COUNT=0
  NEW_POSTS=0
  
  while IFS= read -r POST_JSON; do
    if [ -z "${POST_JSON}" ]; then
      continue
    fi
    
    # Extract post info using our clean functions
    POST_ID=$(extract_id "$POST_JSON")
    TITLE=$(extract_title "$POST_JSON")
    
    if [ -z "${POST_ID}" ]; then
      echo "WARNING: Could not extract post ID from JSON data"
      continue
    fi
    
    echo "Found post ID: ${POST_ID}, Title: ${TITLE}"
    POSTS_COUNT=$((POSTS_COUNT+1))
    
    # Skip if already processed
    if is_processed "${POST_ID}"; then
      echo "Post ${POST_ID} (${TITLE}) already processed, skipping"
      continue
    fi
    
    echo "Found new post: ${TITLE} (${POST_ID})"
    NEW_POSTS=$((NEW_POSTS+1))
    
    # Try to download the post with proper URL
    echo "Downloading ${TITLE}..."
    POST_URL="https://www.patreon.com/posts/${POST_ID}"
    echo "Download URL: ${POST_URL}"
    
    # Download attempt with advanced format selection
    if yt-dlp --cookies "${COOKIES_FILE}" --simulate "${POST_URL}" >/dev/null 2>&1; then
      echo "Found video content in post ${POST_ID}"
      
      # Download the video with best format
      yt-dlp --cookies "${COOKIES_FILE}" --ignore-errors --no-playlist \
        --format "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
        -o "${DOWNLOAD_DIR}/%(uploader)s/%(title)s.%(ext)s" "${POST_URL}"
      
      DOWNLOAD_RESULT=$?
      
      if [ ${DOWNLOAD_RESULT} -eq 0 ]; then
        echo "Successfully downloaded post ${POST_ID}"
        mark_processed "${POST_ID}"
      else
        echo "Failed to download post ${POST_ID}, will try again next time"
      fi
    else
      echo "No video content found in post ${POST_ID}"
      mark_processed "${POST_ID}"
    fi
    
    # Sleep between downloads to be nice
    sleep 2
  done < "${POSTS_LIST}"
  
  rm "${POSTS_LIST}"
  
  # Limit size of processed file
  if [ $(wc -l < "${PROCESSED_FILE}") -gt 1000 ]; then
    tail -n 1000 "${PROCESSED_FILE}" > "${PROCESSED_FILE}.tmp"
    mv "${PROCESSED_FILE}.tmp" "${PROCESSED_FILE}"
  fi
  
  echo "Check completed: ${POSTS_COUNT} posts checked, ${NEW_POSTS} new downloads"
  echo "Waiting ${CHECK_INTERVAL} seconds until next check..."
  sleep "${CHECK_INTERVAL}"
done