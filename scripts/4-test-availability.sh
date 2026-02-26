#!/bin/bash

# MÔ TẢ: Gửi GET requests liên tục để test availability và monitor uptime
# Dùng để verify zero downtime trong rolling update
#
# CÁCH DÙNG:
# ./4-test-availability.sh [URL] [INTERVAL]
#
# VÍ DỤ:
# ./4-test-availability.sh http://localhost:30081 1
# ./4-test-availability.sh http://localhost:30081 0.1
#
# Nhấn Ctrl+C để dừng
# ============================================

URL=${1:-http://localhost:30081}
INTERVAL=${2:-1}

echo "🧪 Testing availability"
echo "URL: $URL"
echo "Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

SUCCESS=0
FAILED=0

trap 'echo ""; echo "📊 Results: Success=$SUCCESS Failed=$FAILED"; exit' INT

while true; do
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null --max-time 5 "$URL/api/accounts")
    
    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
        echo "[$(date '+%H:%M:%S')] ✅ SUCCESS - Total: $((SUCCESS + FAILED)) | Success: $SUCCESS | Failed: $FAILED"
    else
        FAILED=$((FAILED + 1))
        echo "[$(date '+%H:%M:%S')] ❌ FAILED HTTP $HTTP_CODE - Total: $((SUCCESS + FAILED)) | Success: $SUCCESS | Failed: $FAILED"
    fi
    
    sleep $INTERVAL
done
