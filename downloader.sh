#!/bin/bash

CONFIG_DIR="/data/config"
DOWNLOAD_DIR="/data/downloads"
COOKIES_FILE="${CONFIG_DIR}/cookies.txt"
TOKEN_FILE="${CONFIG_DIR}/token.txt"
PROCESSED_FILE="${CONFIG_DIR}/processed_posts.txt"
MAX_POSTS=${MAX_POSTS:-20}
CHECK_INTERVAL=${CHECK_INTERVAL:-3600}
CREATOR_URL=${CREATOR_URL:-""}
ACCESS_TOKEN=${ACCESS_TOKEN:-""}
REFRESH_TOKEN=${REFRESH_TOKEN:-""}

# Debug information
echo "DEBUG: Environment variables received:"
echo "DEBUG: CREATOR_URL=$CREATOR_URL"
echo "DEBUG: MAX_POSTS=$MAX_POSTS"
echo "DEBUG: CHECK_INTERVAL=$CHECK_INTERVAL"
echo "DEBUG: ACCESS_TOKEN=${ACCESS_TOKEN:0:5}..." # Only show first 5 chars for security

# Setup
mkdir -p "${CONFIG_DIR}" "${DOWNLOAD_DIR}"
touch "${PROCESSED_FILE}"

# Check for token authentication
if [ -n "${ACCESS_TOKEN}" ]; then
  echo "Using provided access token from environment variables"
  # Store token in file for yt-dlp
  echo "${ACCESS_TOKEN}" > "${TOKEN_FILE}"
elif [ -f "${TOKEN_FILE}" ]; then
  echo "Using existing token file from ${TOKEN_FILE}"
  ACCESS_TOKEN=$(cat "${TOKEN_FILE}")
elif [ -f "${COOKIES_FILE}" ]; then
  echo "Using cookies authentication as fallback"
else
  echo "Warning: No authentication method provided. Need either ACCESS_TOKEN or cookies.txt"
  echo "You may need to provide authentication to access patron-only content"
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

# Function to use appropriate authentication method
download_with_auth() {
  local url="$1"
  local output_template="$2"
  local options="$3"
  
  if [ -n "${ACCESS_TOKEN}" ]; then
    # Use token-based authentication with headers
    yt-dlp --add-headers "Authorization: Bearer ${ACCESS_TOKEN}" $options "$url" -o "$output_template"
  elif [ -f "${COOKIES_FILE}" ]; then
    # Fallback to cookies-based authentication
    yt-dlp --cookies "${COOKIES_FILE}" $options "$url" -o "$output_template"
  else
    # Try without authentication
    yt-dlp $options "$url" -o "$output_template"
  fi
  
  return $?
}

# Simulate with auth
simulate_with_auth() {
  local url="$1"
  
  if [ -n "${ACCESS_TOKEN}" ]; then
    yt-dlp --add-headers "Authorization: Bearer ${ACCESS_TOKEN}" --simulate "$url" >/dev/null 2>&1
  elif [ -f "${COOKIES_FILE}" ]; then
    yt-dlp --cookies "${COOKIES_FILE}" --simulate "$url" >/dev/null 2>&1
  else
    yt-dlp --simulate "$url" >/dev/null 2>&1
  fi
  
  return $?
}

# Get posts list with auth
get_posts_list() {
  local url="$1"
  local output_file="$2"
  
  if [ -n "${ACCESS_TOKEN}" ]; then
    yt-dlp --dump-json --playlist-items "1-${MAX_POSTS}" \
      --add-headers "Authorization: Bearer ${ACCESS_TOKEN}" \
      "$url" 2>/dev/null > "$output_file" || true
  elif [ -f "${COOKIES_FILE}" ]; then
    yt-dlp --dump-json --playlist-items "1-${MAX_POSTS}" \
      --cookies "${COOKIES_FILE}" \
      "$url" 2>/dev/null > "$output_file" || true
  else
    yt-dlp --dump-json --playlist-items "1-${MAX_POSTS}" \
      "$url" 2>/dev/null > "$output_file" || true
  fi
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
  get_posts_list "${POSTS_URL}" "${POSTS_LIST}"
  
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
    if simulate_with_auth "${POST_URL}"; then
      echo "Found video content in post ${POST_ID}"
      
      # Download the video with best format
      download_with_auth "${POST_URL}" \
        "${DOWNLOAD_DIR}/%(uploader)s/%(title)s.%(ext)s" \
        "--ignore-errors --no-playlist --format \"bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best\""
      
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