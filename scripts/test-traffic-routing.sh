#!/bin/bash

URL=${1:-http://192.168.10.142:30081}
DEPLOYMENT=${2:-banking-good}

echo "🔍 Testing Traffic Routing During Pod Termination"
echo "URL: $URL"
echo ""

# Get all pod IPs
echo "📋 Current pods and IPs:"
kubectl get pods -l app=$DEPLOYMENT -o custom-columns=NAME:.metadata.name,IP:.status.podIP,STATUS:.status.phase

echo ""
echo "🎯 Tracking which pods receive traffic..."
echo ""

# Track requests per pod
declare -A POD_REQUESTS

# Function to send request and track pod
send_request() {
    RESPONSE=$(curl -s $URL/api/pod-info 2>/dev/null)
    if [ $? -eq 0 ]; then
        POD_IP=$(echo $RESPONSE | jq -r .podIp 2>/dev/null)
        POD_NAME=$(echo $RESPONSE | jq -r .podName 2>/dev/null)
        
        if [ "$POD_IP" != "null" ] && [ -n "$POD_IP" ]; then
            POD_REQUESTS[$POD_IP]=$((${POD_REQUESTS[$POD_IP]:-0} + 1))
            echo "[$(date '+%H:%M:%S')] ✅ Request served by: $POD_NAME ($POD_IP)"
        else
            echo "[$(date '+%H:%M:%S')] ❌ Failed to get pod info"
        fi
    else
        echo "[$(date '+%H:%M:%S')] ❌ Request failed"
    fi
}

# Send initial requests to establish baseline
echo "Phase 1: Baseline (10 requests)"
for i in {1..10}; do
    send_request
    sleep 0.5
done

echo ""
echo "📊 Baseline traffic distribution:"
for pod_ip in "${!POD_REQUESTS[@]}"; do
    echo "   Pod $pod_ip: ${POD_REQUESTS[$pod_ip]} requests"
done

# Select a pod to delete
TARGET_POD=$(kubectl get pods -l app=$DEPLOYMENT -o name | head -1 | cut -d'/' -f2)
TARGET_IP=$(kubectl get pod $TARGET_POD -o jsonpath='{.status.podIP}')

echo ""
echo "🎯 Target pod for deletion: $TARGET_POD ($TARGET_IP)"
echo ""

# Reset counters
declare -A POD_REQUESTS_AFTER

# Delete pod in background
echo "Phase 2: Deleting pod and monitoring traffic..."
kubectl delete pod $TARGET_POD --wait=false &
DELETE_PID=$!

# Send requests during termination
for i in {1..30}; do
    RESPONSE=$(curl -s $URL/api/pod-info 2>/dev/null)
    if [ $? -eq 0 ]; then
        POD_IP=$(echo $RESPONSE | jq -r .podIp 2>/dev/null)
        POD_NAME=$(echo $RESPONSE | jq -r .podName 2>/dev/null)
        
        if [ "$POD_IP" != "null" ] && [ -n "$POD_IP" ]; then
            POD_REQUESTS_AFTER[$POD_IP]=$((${POD_REQUESTS_AFTER[$POD_IP]:-0} + 1))
            
            if [ "$POD_IP" = "$TARGET_IP" ]; then
                echo "[$(date '+%H:%M:%S')] ⚠️  Request to TERMINATING pod: $POD_NAME ($POD_IP)"
            else
                echo "[$(date '+%H:%M:%S')] ✅ Request to healthy pod: $POD_NAME ($POD_IP)"
            fi
        fi
    else
        echo "[$(date '+%H:%M:%S')] ❌ Request failed"
    fi
    sleep 0.5
done

wait $DELETE_PID 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Traffic distribution during termination:"
for pod_ip in "${!POD_REQUESTS_AFTER[@]}"; do
    COUNT=${POD_REQUESTS_AFTER[$pod_ip]}
    if [ "$pod_ip" = "$TARGET_IP" ]; then
        echo "   ⚠️  Terminating pod $pod_ip: $COUNT requests"
        TERMINATING_REQUESTS=$COUNT
    else
        echo "   ✅ Healthy pod $pod_ip: $COUNT requests"
    fi
done

echo ""
if [ "${TERMINATING_REQUESTS:-0}" -eq 0 ]; then
    echo "✅ PASS: No traffic routed to terminating pod"
    echo "   Kubernetes correctly removed pod from endpoints"
else
    echo "❌ FAIL: $TERMINATING_REQUESTS requests routed to terminating pod"
    echo "   Pod may still be in endpoints during termination"
fi

echo ""
echo "Current pods:"
kubectl get pods -l app=$DEPLOYMENT -o custom-columns=NAME:.metadata.name,IP:.status.podIP,STATUS:.status.phase
