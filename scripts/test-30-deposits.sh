#!/bin/bash

# Test 30 concurrent deposits to see behavior during pod scale down
# Usage: ./test-30-deposits.sh <base-url> <deployment-name> <scale-at-request>
# Example: ./test-30-deposits.sh http://localhost:30081 banking-good 5

BASE_URL="${1:-http://localhost:30081}"
DEPLOYMENT="${2:-banking-good}"
SCALE_AT="${3:-5}"  # Scale down sau khi gửi request thứ mấy

echo "🧪 Test 30 Concurrent Deposits - Auto Scale Down"
echo "===================================================="
echo "Base URL: $BASE_URL"
echo "Deployment: $DEPLOYMENT"
echo "Scale down sau request thứ: $SCALE_AT"
echo ""

# Đếm transaction trước
echo "📊 Transaction count TRƯỚC test:"
BEFORE=$(curl -s "$BASE_URL/api/transactions" | jq 'length')
echo "   $BEFORE transactions"
echo ""

# Tạo file log
LOG_FILE="test-30-deposits-$(date +%s).log"
SCALE_LOG="scale-down-$(date +%s).log"
echo "📝 Log file: $LOG_FILE"
echo "📝 Scale log: $SCALE_LOG"
echo ""

# Gửi 30 requests (mỗi giây 1 request)
echo "🚀 Gửi 30 requests (1 request/giây)..."
echo "   Mỗi request mất 10s để xử lý"
echo "   Deployment sẽ scale down về 0 sau request thứ $SCALE_AT"
echo ""

SCALE_TRIGGERED=false
START_TIME=$(date +%s)

for i in {1..30}; do
    # Tính thời điểm gửi chính xác
    TARGET_TIME=$((START_TIME + i - 1))
    CURRENT_TIME=$(date +%s)
    SLEEP_TIME=$((TARGET_TIME - CURRENT_TIME))
    
    # Sleep để đồng bộ thời gian
    if [ $SLEEP_TIME -gt 0 ]; then
        sleep $SLEEP_TIME
    fi
    
    TIMESTAMP=$(date +%H:%M:%S.%3N)
    echo "[$TIMESTAMP] Request $i/30 - Sending..."
    
    # Gửi request background
    (
        START=$(date +%s)
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/deposit" \
            -H "Content-Type: application/json" \
            -d "{\"accountNumber\": \"ACC002\", \"amount\": $((i * 1000))}" 2>&1)
        END=$(date +%s)
        DURATION=$((END - START))
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | head -n-1)
        
        echo "[$(date +%H:%M:%S.%3N)] Request $i - HTTP $HTTP_CODE - Duration: ${DURATION}s - Body: $BODY" >> "$LOG_FILE"
    ) &
    
    # Scale down sau khi gửi request thứ SCALE_AT
    if [ $i -eq $SCALE_AT ] && [ "$SCALE_TRIGGERED" = false ]; then
        SCALE_TRIGGERED=true
        (
            sleep 0.5  # Chờ 0.5s để request bắt đầu xử lý
            SCALE_TIME=$(date +%H:%M:%S.%3N)
            echo "" | tee -a "$SCALE_LOG"
            echo "===========================================" | tee -a "$SCALE_LOG"
            echo "❌ [$SCALE_TIME] SCALING DOWN TO 0" | tee -a "$SCALE_LOG"
            echo "===========================================" | tee -a "$SCALE_LOG"
            echo "Requests đang xử lý: 1-$SCALE_AT" | tee -a "$SCALE_LOG"
            echo "Requests chưa gửi: $((SCALE_AT + 1))-30" | tee -a "$SCALE_LOG"
            echo "" | tee -a "$SCALE_LOG"
            
            kubectl scale deployment $DEPLOYMENT --replicas=0 2>&1 | tee -a "$SCALE_LOG"
            
            echo "" | tee -a "$SCALE_LOG"
            echo "✅ Scaled down at $SCALE_TIME" | tee -a "$SCALE_LOG"
            echo "===========================================" | tee -a "$SCALE_LOG"
        ) &
    fi
done

echo ""
echo "⏳ Chờ tất cả requests hoàn thành (tối đa 30s)..."
sleep 30

echo ""
echo "📊 Transaction count SAU test:"
AFTER=$(curl -s "$BASE_URL/api/transactions" 2>/dev/null | jq 'length' 2>/dev/null)
if [ -z "$AFTER" ] || [ "$AFTER" = "null" ]; then
    echo "   ⚠️  Không thể lấy transaction count (service không khả dụng)"
    SERVICE_DOWN=true
    AFTER=$BEFORE
else
    echo "   $AFTER transactions"
    SERVICE_DOWN=false
fi
echo ""

# Phân tích log trước
HTTP_200=$(grep -c "HTTP 200" "$LOG_FILE" 2>/dev/null || echo 0)
HTTP_200=$(echo $HTTP_200 | tr -d '\n\r ')
HTTP_000=$(grep -c "HTTP 000" "$LOG_FILE" 2>/dev/null || echo 0)
HTTP_000=$(echo $HTTP_000 | tr -d '\n\r ')
HTTP_503=$(grep -c "HTTP 503" "$LOG_FILE" 2>/dev/null || echo 0)
HTTP_503=$(echo $HTTP_503 | tr -d '\n\r ')

# Tính toán
if [ "$SERVICE_DOWN" = true ]; then
    # Dùng log để tính
    SUCCESS=$HTTP_200
    FAILED=$((30 - SUCCESS))
    
    echo "📈 Kết quả (từ logs vì service down):"
    echo "   Trước:    $BEFORE transactions"
    echo "   Sau:      Không thể kiểm tra (service scaled to 0)"
    echo "   Success:  $SUCCESS/30 ✅ (từ HTTP 200 trong log)"
    echo "   Failed:   $FAILED/30 ❌"
else
    # Dùng database để tính
    SUCCESS=$((AFTER - BEFORE))
    FAILED=$((30 - SUCCESS))
    
    echo "📈 Kết quả:"
    echo "   Trước:    $BEFORE transactions"
    echo "   Sau:      $AFTER transactions"
    echo "   Success:  $SUCCESS/30 ✅"
    echo "   Failed:   $FAILED/30 ❌"
fi
echo ""

# Phân tích log
echo "📋 Phân tích chi tiết (từ log):"
echo ""
echo "   HTTP 200 (Success):       $HTTP_200"
echo "   HTTP 000 (Failed):        $HTTP_000"
echo "   HTTP 503 (Unavailable):   $HTTP_503"

echo "📄 Chi tiết:"
echo "   Request log: $LOG_FILE"
echo "   Scale log:   $SCALE_LOG"
echo ""

if [ "$SUCCESS" -eq 30 ]; then
    echo "✅ PASS: Tất cả 30 transactions đều thành công"
elif [ "$SUCCESS" -gt 0 ]; then
    echo "⚠️  PARTIAL: $SUCCESS/30 transactions thành công"
else
    echo "❌ FAIL: Tất cả transactions đều thất bại"
fi

echo ""
echo "📝 Lưu ý: Nếu service đã scaled to 0, kiểm tra logs để xác định kết quả thực tế."
