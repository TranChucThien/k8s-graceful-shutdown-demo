# Graceful Shutdown Drain Contract - Verification Scenarios

## Drain Contract Definition

Graceful shutdown MUST guarantee these 4 invariants in order:

### 1. Stop new traffic first (Kubernetes routing level)
- Kubernetes removes pod from Service endpoints
- No new connections routed to terminating pod

### 2. Stop accepting new work (Application level)
- Application marks itself as "not ready"
- Readiness probe returns failure
- Existing connections can finish, but no new requests accepted

### 3. Finish or cancel in-flight work within bounded time
- All in-flight requests complete successfully
- Bounded by `terminationGracePeriodSeconds`
- For banking: 10s transaction + 20s buffer = 30s minimum

### 4. Exit before SIGKILL
- Application exits gracefully
- Before `terminationGracePeriodSeconds` expires
- Otherwise Kubernetes sends SIGKILL (force kill)

---

## Verification Scenarios

### Scenario 1: Verify "Stop New Traffic First"
**Goal:** Confirm Kubernetes stops routing BEFORE pod terminates

```bash
# Terminal 1: Monitor pod events
kubectl get pods -w

# Terminal 2: Send continuous requests
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.2

# Terminal 3: Delete a pod and watch logs
POD=$(kubectl get pods -l app=banking-good -o name | head -1)
kubectl logs -f $POD &
kubectl delete $POD

# Expected behavior:
# 1. Pod status: Running -> Terminating
# 2. Pod removed from endpoints immediately
# 3. No new requests reach terminating pod
# 4. Existing requests complete successfully
# 5. Test shows 100% success rate

# Verify endpoints:
kubectl get endpoints banking-good -w
# Terminating pod IP should disappear from endpoints
```

**Verification Commands:**
```bash
# Check if pod is in endpoints
kubectl get endpoints banking-good -o json | jq '.subsets[].addresses[].ip'

# Check pod IP
kubectl get pod <pod-name> -o jsonpath='{.status.podIP}'

# After deletion, pod IP should NOT be in endpoints
```

---

### Scenario 2: Verify "Stop Accepting New Work"
**Goal:** Confirm readiness probe fails during shutdown

```bash
# Terminal 1: Watch readiness probe status
watch -n 1 'kubectl get pods -o wide'

# Terminal 2: Continuous health checks
while true; do
  POD_IP=$(kubectl get pod <pod-name> -o jsonpath='{.status.podIP}')
  curl -s http://$POD_IP:8080/actuator/health/readiness | jq .
  sleep 1
done

# Terminal 3: Delete pod
kubectl delete pod <pod-name>

# Expected behavior:
# 1. Readiness probe returns {"status":"UP"} initially
# 2. After SIGTERM, readiness returns {"status":"DOWN"}
# 3. Pod marked as NotReady
# 4. No new requests accepted
# 5. Existing requests still complete
```

**Verification Script:**
```bash
#!/bin/bash
POD=$(kubectl get pods -l app=banking-good -o name | head -1 | cut -d'/' -f2)
POD_IP=$(kubectl get pod $POD -o jsonpath='{.status.podIP}')

echo "Monitoring readiness probe for $POD ($POD_IP)"

# Monitor readiness
(while true; do
  STATUS=$(curl -s http://$POD_IP:8080/actuator/health/readiness | jq -r .status 2>/dev/null || echo "UNREACHABLE")
  echo "[$(date '+%H:%M:%S')] Readiness: $STATUS"
  sleep 1
done) &
MONITOR_PID=$!

sleep 5
echo "Deleting pod..."
kubectl delete pod $POD

sleep 30
kill $MONITOR_PID

# Expected output:
# [03:00:00] Readiness: UP
# [03:00:01] Readiness: UP
# Deleting pod...
# [03:00:05] Readiness: DOWN  <- Should change to DOWN
# [03:00:06] Readiness: DOWN
# [03:00:20] Readiness: UNREACHABLE  <- Pod terminated
```

---

### Scenario 3: Verify "Finish In-Flight Work Within Bounded Time"
**Goal:** Confirm all 10s transactions complete successfully

```bash
# Terminal 1: Send long-running transactions
./test-deposit-rolling.sh http://192.168.10.142:30081 0.5

# Terminal 2: Monitor transactions in real-time
watch -n 1 'kubectl exec -it $(kubectl get pods -l app=banking-good -o name | head -1) -- curl -s http://localhost:8080/api/transactions | jq ".[0:5]"'

# Terminal 3: Delete pod during transaction
# Wait for a transaction to start, then immediately delete pod
kubectl delete pod <pod-name>

# Expected behavior:
# 1. Transaction starts at T=0
# 2. Pod receives SIGTERM at T=2
# 3. Transaction continues processing
# 4. Transaction completes at T=10 (SUCCESS)
# 5. Pod terminates at T=30 (after preStop + grace period)
# 6. Test shows 100% success, 0% failed

# Verify transaction completed:
kubectl exec -it $(kubectl get pods -l app=banking-good -o name | head -1) -- \
  curl -s http://localhost:8080/api/transactions | jq '.[] | select(.status=="COMPLETED")'
```

**Detailed Verification Script:**
```bash
#!/bin/bash

echo "Testing in-flight transaction completion during shutdown"

# Start a 10s transaction
echo "Starting 10s deposit transaction..."
(curl -X POST http://192.168.10.142:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001","amount":5000}' \
  -w "\nHTTP: %{http_code}\nTime: %{time_total}s\n") &
CURL_PID=$!

# Wait 2s then delete pod
sleep 2
POD=$(kubectl get pods -l app=banking-good -o name | head -1)
echo "Deleting pod $POD while transaction is in-flight..."
kubectl delete $POD &

# Wait for transaction to complete
wait $CURL_PID

# Expected output:
# Starting 10s deposit transaction...
# Deleting pod banking-good-xxx while transaction is in-flight...
# {"id":123,"accountNumber":"ACC001","amount":5000,"status":"COMPLETED"}
# HTTP: 200
# Time: 10.xxx s  <- Should complete successfully
```

---

### Scenario 4: Verify "Exit Before SIGKILL"
**Goal:** Confirm pod exits gracefully before terminationGracePeriodSeconds

```bash
# Terminal 1: Monitor pod lifecycle with timestamps
kubectl get pods -w --output-watch-events | while read line; do
  echo "[$(date '+%H:%M:%S')] $line"
done

# Terminal 2: Send requests
./test-concurrent-users.sh http://192.168.10.142:30081 5 0.5

# Terminal 3: Delete pod and measure time
START=$(date +%s)
POD=$(kubectl get pods -l app=banking-good -o name | head -1)
kubectl delete $POD
kubectl wait --for=delete $POD --timeout=70s
END=$(date +%s)
DURATION=$((END - START))
echo "Pod terminated in ${DURATION}s"

# Expected behavior:
# 1. SIGTERM sent at T=0
# 2. preStop hook runs: sleep 20s (T=0 to T=20)
# 3. Application processes remaining requests (T=20 to T=30)
# 4. Application exits gracefully at T=30
# 5. Total time < 60s (terminationGracePeriodSeconds)
# 6. No SIGKILL needed

# If DURATION > 60s, SIGKILL was sent (BAD)
# If DURATION < 60s, graceful shutdown (GOOD)
```

**Verification with Pod Events:**
```bash
# Check pod events for SIGKILL
kubectl describe pod <pod-name> | grep -A 10 Events

# Good output (no SIGKILL):
# Events:
#   Type    Reason     Age   Message
#   Normal  Killing    30s   Stopping container banking
#   Normal  Preempting 30s   Preempting pod

# Bad output (SIGKILL sent):
# Events:
#   Type     Reason     Age   Message
#   Warning  Killing    60s   Container banking failed liveness probe, will be restarted
#   Warning  Unhealthy  60s   Liveness probe failed
```

---

## Complete Verification Test Suite

### Test 1: Full Drain Contract Verification
```bash
#!/bin/bash

echo "=== DRAIN CONTRACT VERIFICATION ==="
echo ""

# Setup
kubectl apply -f k8s-good.yaml
kubectl wait --for=condition=ready pod -l app=banking-good --timeout=60s

# Start continuous load
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.2 > /tmp/load-test.log 2>&1 &
LOAD_PID=$!
sleep 10

echo "1. Testing: Stop new traffic first"
POD=$(kubectl get pods -l app=banking-good -o name | head -1 | cut -d'/' -f2)
POD_IP=$(kubectl get pod $POD -o jsonpath='{.status.podIP}')

# Check pod is in endpoints
BEFORE=$(kubectl get endpoints banking-good -o json | jq -r ".subsets[].addresses[].ip" | grep $POD_IP)
echo "   Pod $POD_IP in endpoints: $BEFORE"

# Delete pod
kubectl delete pod $POD --wait=false

# Wait 5s and check endpoints again
sleep 5
AFTER=$(kubectl get endpoints banking-good -o json | jq -r ".subsets[].addresses[].ip" | grep $POD_IP || echo "NOT_FOUND")
echo "   Pod $POD_IP in endpoints after 5s: $AFTER"

if [ "$AFTER" = "NOT_FOUND" ]; then
  echo "   ✅ PASS: Pod removed from endpoints"
else
  echo "   ❌ FAIL: Pod still in endpoints"
fi

echo ""
echo "2. Testing: Stop accepting new work"
# Readiness should fail after SIGTERM
sleep 2
READINESS=$(curl -s http://$POD_IP:8080/actuator/health/readiness 2>/dev/null | jq -r .status || echo "UNREACHABLE")
echo "   Readiness status: $READINESS"

if [ "$READINESS" = "DOWN" ] || [ "$READINESS" = "UNREACHABLE" ]; then
  echo "   ✅ PASS: Not accepting new work"
else
  echo "   ❌ FAIL: Still accepting work"
fi

echo ""
echo "3. Testing: Finish in-flight work"
# Wait for pod to terminate
kubectl wait --for=delete pod/$POD --timeout=70s
echo "   ✅ Pod terminated gracefully"

echo ""
echo "4. Testing: Exit before SIGKILL"
# Check if any SIGKILL in events
SIGKILL=$(kubectl get events --field-selector involvedObject.name=$POD | grep -i "sigkill" || echo "")
if [ -z "$SIGKILL" ]; then
  echo "   ✅ PASS: No SIGKILL, graceful exit"
else
  echo "   ❌ FAIL: SIGKILL detected"
fi

# Stop load test
kill $LOAD_PID
wait $LOAD_PID 2>/dev/null

echo ""
echo "=== RESULTS ==="
grep "Final Results" -A 4 /tmp/load-test.log

# Expected: 100% success, 0% failed, 0% timeout
```

---

## Timeline Diagram

```
Time    Kubernetes              Application             Requests
────────────────────────────────────────────────────────────────
T=0     DELETE pod              Running                 ✅ Processing
        Send SIGTERM            
                                
T=0     Remove from endpoints   preStop: sleep 20s      ✅ Processing
        (no new traffic)        
                                
T=20                            preStop done            ✅ Processing
                                Readiness: DOWN         
                                Stop accepting new      
                                
T=30                            Finish in-flight        ✅ Complete
                                Exit gracefully         
                                
T=30    Pod terminated          -                       -
        (before T=60)
        
T=60    Would send SIGKILL      -                       -
        (not needed)
```

---

## Success Criteria

### ✅ All 4 invariants verified:
1. Pod removed from endpoints within 5s of SIGTERM
2. Readiness probe returns DOWN after preStop
3. All in-flight transactions complete (100% success)
4. Pod exits before terminationGracePeriodSeconds (no SIGKILL)

### ✅ Metrics:
- Success rate: 100%
- Failed rate: 0%
- Timeout rate: 0%
- Shutdown time: < terminationGracePeriodSeconds (60s)
- No SIGKILL events in pod logs

### ❌ Failure indicators:
- Any failed/timeout requests during shutdown
- SIGKILL in pod events
- Shutdown time = terminationGracePeriodSeconds (force killed)
- Pod still in endpoints after SIGTERM
- Readiness probe still UP after SIGTERM
