#!/bin/bash

# MÔ TẢ: Gửi deposit requests liên tục (10s mỗi transaction) để test graceful shutdown
# Dùng để verify transaction không bị mất khi delete pod
#
# CÁCH DÙNG:
# ./3-test-deposit.sh [URL] [INTERVAL]
#
# VÍ DỤ:
# ./3-test-deposit.sh http://localhost:30081 2
# ./3-test-deposit.sh http://192.168.10.142:30081 0.5
#
# Nhấn Ctrl+C để dừng
# ============================================

URL=${1:-http://localhost:30081}
INTERVAL=${2:-2}

echo "🧪 Testing deposit (10s transactions)"
echo "URL: $URL"
echo "Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

SUCCESS=0
FAILED=0

trap 'echo ""; echo "📊 Results: Success=$SUCCESS Failed=$FAILED"; exit' INT

while true; do
    AMOUNT=$((RANDOM % 5 + 1))000
    
    echo "[$(date '+%H:%M:%S')] 🔄 Sending deposit $AMOUNT VND..."
    
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null --max-time 15 \
        -X POST "$URL/api/deposit" \
        -H "Content-Type: application/json" \
        -d "{\"accountNumber\":\"ACC001\",\"amount\":$AMOUNT}")
    
    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
        echo "[$(date '+%H:%M:%S')] ✅ SUCCESS - Total: $((SUCCESS + FAILED)) | Success: $SUCCESS | Failed: $FAILED"
    else
        FAILED=$((FAILED + 1))
        echo "[$(date '+%H:%M:%S')] ❌ FAILED HTTP $HTTP_CODE - Total: $((SUCCESS + FAILED)) | Success: $SUCCESS | Failed: $FAILED"
    fi
    
    sleep $INTERVAL
done
