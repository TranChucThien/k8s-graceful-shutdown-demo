#!/bin/bash

URL=${1:-http://localhost:30081}
USERS=${2:-5}
INTERVAL=${3:-0.5}

echo "🧪 Testing Rolling Update with Multiple Users"
echo "URL: $URL"
echo "Concurrent Users: $USERS"
echo "Interval per user: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

TEMP_DIR="/tmp/banking-test-$$"
mkdir -p "$TEMP_DIR"

cleanup() {
    echo ""
    echo "📊 Collecting results..."
    
    TOTAL=0
    SUCCESS=0
    FAILED=0
    TIMEOUT=0
    
    for i in $(seq 1 $USERS); do
        if [ -f "$TEMP_DIR/user-$i.log" ]; then
            USER_SUCCESS=$(grep -c "✅ SUCCESS" "$TEMP_DIR/user-$i.log" || echo 0)
            USER_FAILED=$(grep -c "❌ FAILED" "$TEMP_DIR/user-$i.log" || echo 0)
            USER_TIMEOUT=$(grep -c "⏱️  TIMEOUT" "$TEMP_DIR/user-$i.log" || echo 0)
            
            SUCCESS=$((SUCCESS + USER_SUCCESS))
            FAILED=$((FAILED + USER_FAILED))
            TIMEOUT=$((TIMEOUT + USER_TIMEOUT))
        fi
    done
    
    TOTAL=$((SUCCESS + FAILED + TIMEOUT))
    
    echo ""
    echo "📊 Final Results:"
    echo "Total Requests: $TOTAL"
    echo "✅ Success: $SUCCESS ($((SUCCESS * 100 / TOTAL))%)"
    echo "❌ Failed: $FAILED ($((FAILED * 100 / TOTAL))%)"
    echo "⏱️  Timeout: $TIMEOUT ($((TIMEOUT * 100 / TOTAL))%)"
    
    rm -rf "$TEMP_DIR"
    kill 0
    exit
}

trap cleanup INT

run_user() {
    USER_ID=$1
    ACCOUNTS=("ACC001" "ACC002" "ACC003")
    
    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        ACCOUNT=${ACCOUNTS[$((RANDOM % 3))]}
        AMOUNT=$((RANDOM % 5 + 1))000
        
        RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" --max-time 15 \
            -X POST "$URL/api/deposit" \
            -H "Content-Type: application/json" \
            -d "{\"accountNumber\":\"$ACCOUNT\",\"amount\":$AMOUNT}" 2>&1)
        EXIT_CODE=$?
        
        if [ $EXIT_CODE -eq 0 ]; then
            HTTP_CODE=$(echo "$RESPONSE" | tail -2 | head -1)
            TIME=$(echo "$RESPONSE" | tail -1)
            
            if [ "$HTTP_CODE" = "200" ]; then
                TX_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
                echo "[$TIMESTAMP] User#$USER_ID ✅ SUCCESS - TX#$TX_ID - $ACCOUNT - ${TIME}s"
                echo "✅ SUCCESS" >> "$TEMP_DIR/user-$USER_ID.log"
            else
                echo "[$TIMESTAMP] User#$USER_ID ❌ FAILED - HTTP $HTTP_CODE"
                echo "❌ FAILED" >> "$TEMP_DIR/user-$USER_ID.log"
            fi
        else
            echo "[$TIMESTAMP] User#$USER_ID ⏱️  TIMEOUT"
            echo "⏱️  TIMEOUT" >> "$TEMP_DIR/user-$USER_ID.log"
        fi
        
        sleep $INTERVAL
    done
}

for i in $(seq 1 $USERS); do
    run_user $i &
done

wait
