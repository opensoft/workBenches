#!/bin/bash
set -uo pipefail

DATASET_ID="ds.20b76a0b009543d6a119655d9ab41b12"
DOWNLOAD_DIR="/workspace/basespace_data"
LOG_FILE="/workspace/basespace_data/.download.log"
MAX_RETRIES=100
RETRY_DELAY=30

mkdir -p "$DOWNLOAD_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

ATTEMPT=0

while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    log "===== Download attempt $ATTEMPT/$MAX_RETRIES ====="

    # bs download skips files that already exist (same size),
    # so each retry only downloads what's missing
    if bs download dataset \
        --id "$DATASET_ID" \
        --output "$DOWNLOAD_DIR" \
        --no-progress-bars \
        --concurrency high \
        2>&1 | tee -a "$LOG_FILE"; then
        log "===== DOWNLOAD COMPLETE ====="
        exit 0
    else
        EXIT_CODE=$?
        log "Download interrupted or failed (exit code: $EXIT_CODE)"
        log "Retrying in ${RETRY_DELAY}s... (existing files will be skipped)"
        sleep $RETRY_DELAY
    fi
done

log "ERROR: Failed after $MAX_RETRIES attempts"
exit 1
