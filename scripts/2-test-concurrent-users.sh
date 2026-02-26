#!/bin/bash

# MÔ TẢ: Gửi deposit requests đồng thời từ nhiều users để test concurrent traffic
# Dùng để test graceful shutdown và rolling update với tải cao
#
# CÁCH DÙNG:
# ./2-test-concurrent-users.sh [URL] [USERS] [INTERVAL]
#
# VÍ DỤ:
# ./2-test-concurrent-users.sh http://localhost:30081 5 0.5
# ./2-test-concurrent-users.sh http://192.168.10.142:30081 10 1
#
# Nhấn Ctrl+C để dừng
# ============================================

URL=${1:-http://localhost:30081}
USERS=${2:-5}
INTERVAL=${3:-0.5}

echo "🧪 Testing with $USERS concurrent users"
echo "URL: $URL"
echo "Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

SUCCESS=0
FAILED=0

trap 'echo ""; echo "📊 Results: Success=$SUCCESS Failed=$FAILED"; exit' INT

run_user() {
    USER_ID=$1
    ACCOUNTS=("ACC001" "ACC002" "ACC003")
    
    while true; do
        ACCOUNT=${ACCOUNTS[$((RANDOM % 3))]}
        AMOUNT=$((RANDOM % 5 + 1))000
        
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null --max-time 15 \
            -X POST "$URL/api/deposit" \
            -H "Content-Type: application/json" \
            -d "{\"accountNumber\":\"$ACCOUNT\",\"amount\":$AMOUNT}")
        
        if [ "$HTTP_CODE" = "200" ]; then
            SUCCESS=$((SUCCESS + 1))
            echo "[$(date '+%H:%M:%S')] User#$USER_ID ✅ SUCCESS - $ACCOUNT - Total: $((SUCCESS + FAILED))"
        else
            FAILED=$((FAILED + 1))
            echo "[$(date '+%H:%M:%S')] User#$USER_ID ❌ FAILED HTTP $HTTP_CODE - Total: $((SUCCESS + FAILED))"
        fi
        
        sleep $INTERVAL
    done
}

for i in $(seq 1 $USERS); do
    run_user $i &
done

wait
