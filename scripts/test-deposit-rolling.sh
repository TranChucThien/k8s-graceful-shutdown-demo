#!/bin/bash

URL=${1:-http://localhost:30081}
INTERVAL=${2:-2}
ACCOUNT=${3:-ACC001}

echo "🧪 Testing Rolling Update with Deposit (10s transactions)"
echo "URL: $URL"
echo "Interval: ${INTERVAL}s"
echo "Account: $ACCOUNT"
echo "Press Ctrl+C to stop"
echo ""

SUCCESS=0
FAILED=0
TIMEOUT=0
TOTAL=0

trap 'echo ""; echo "📊 Final Results:"; echo "Total Requests: $TOTAL"; echo "✅ Success: $SUCCESS ($((SUCCESS * 100 / TOTAL))%)"; echo "❌ Failed: $FAILED ($((FAILED * 100 / TOTAL))%)"; echo "⏱️  Timeout: $TIMEOUT ($((TIMEOUT * 100 / TOTAL))%)"; exit' INT

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    TOTAL=$((TOTAL + 1))
    AMOUNT=$((RANDOM % 5 + 1))000
    
    echo "[$TIMESTAMP] 🔄 Sending deposit request: $AMOUNT VND..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" --max-time 15 \
        -X POST "$URL/api/deposit" \
        -H "Content-Type: application/json" \
        -d "{\"accountNumber\":\"$ACCOUNT\",\"amount\":$AMOUNT}" 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        HTTP_CODE=$(echo "$RESPONSE" | tail -2 | head -1)
        TIME=$(echo "$RESPONSE" | tail -1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            SUCCESS=$((SUCCESS + 1))
            TX_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
            echo "[$TIMESTAMP] ✅ SUCCESS - TX#$TX_ID - ${TIME}s - Total: $TOTAL | Success: $SUCCESS | Failed: $FAILED | Timeout: $TIMEOUT"
        else
            FAILED=$((FAILED + 1))
            echo "[$TIMESTAMP] ❌ FAILED - HTTP $HTTP_CODE - Total: $TOTAL | Success: $SUCCESS | Failed: $FAILED | Timeout: $TIMEOUT"
        fi
    else
        TIMEOUT=$((TIMEOUT + 1))
        echo "[$TIMESTAMP] ⏱️  TIMEOUT - Connection failed - Total: $TOTAL | Success: $SUCCESS | Failed: $FAILED | Timeout: $TIMEOUT"
    fi
    
    sleep $INTERVAL
done
