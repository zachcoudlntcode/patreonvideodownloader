FROM python:3.12-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    grep \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN pip install --no-cache-dir yt-dlp

WORKDIR /app

# Copy our script
COPY downloader.sh .
RUN chmod +x downloader.sh

# Create directories
RUN mkdir -p /data/downloads /data/config

# Run our script
CMD ["/app/downloader.sh"]