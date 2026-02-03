# API Endpoints Documentation

## Core Endpoints

### 1. GET /api/accounts
Lấy danh sách tất cả tài khoản

**Response:**
```json
[
  {
    "id": 1,
    "accountNumber": "ACC001",
    "accountHolder": "Nguyen Van A",
    "balance": 1000000,
    "version": 0
  }
]
```

### 2. GET /api/transactions
Lấy lịch sử giao dịch (sắp xếp theo thời gian mới nhất)

**Response:**
```json
[
  {
    "id": 1,
    "accountNumber": "ACC001",
    "type": "DEPOSIT",
    "amount": 100000,
    "status": "COMPLETED",
    "createdAt": "2026-01-29T10:30:00"
  }
]
```

### 3. POST /api/deposit
Nộp tiền vào tài khoản (xử lý 10 giây)

**Request:**
```json
{
  "accountNumber": "ACC001",
  "amount": 100000
}
```

**Response (Success):**
```json
{
  "id": 1,
  "accountNumber": "ACC001",
  "type": "DEPOSIT",
  "amount": 100000,
  "status": "COMPLETED",
  "createdAt": "2026-01-29T10:30:00"
}
```

**Response (Error):**
```
Account not found: ACC999
```

---

## Health Check Endpoints

### 4. GET /actuator/health/readiness
Kiểm tra pod có sẵn sàng nhận traffic không

**Response (Ready):**
```json
{
  "status": "UP"
}
```

**Response (Not Ready - Draining):**
```json
{
  "status": "DOWN"
}
```

**Sử dụng:**
- Kubernetes readinessProbe
- Load balancer health check
- Trả về 503 khi pod đang shutdown

### 5. GET /actuator/health/liveness
Kiểm tra pod còn sống không

**Response:**
```json
{
  "status": "UP"
}
```

**Sử dụng:**
- Kubernetes livenessProbe
- Restart pod nếu fail

### 6. GET /api/health/ready
Custom readiness endpoint (tương tự actuator)

**Response:**
```json
{
  "status": "UP",
  "ready": true
}
```

---

## Graceful Shutdown Endpoints

### 7. GET /api/drain
**PreStop Hook Endpoint** - Ngăn nhận connection mới

**Chức năng:**
- Set readiness flag = false
- Ngừng nhận request mới ngay lập tức
- Request đang xử lý vẫn hoàn thành
- Return HTTP 200 để Kubernetes biết preStop thành công

**Response:**
```json
{
  "status": "draining",
  "message": "Pod is draining - readiness set to FALSE",
  "action": "No new traffic will be accepted"
}
```

**Được gọi bởi:**
```yaml
lifecycle:
  preStop:
    httpGet:
      path: /api/drain
      port: 8080
```

**Luồng hoạt động:**
1. Kubernetes gọi /api/drain khi delete pod
2. ShutdownListener.setNotReady() → ready = false
3. Readiness probe fail → Service ngừng route traffic
4. ShutdownFilter chặn request mới → return 503
5. Request đang xử lý tiếp tục hoàn thành
6. SIGTERM → Spring Boot graceful shutdown

### 8. GET /api/pod-info
Lấy thông tin pod hiện tại

**Response:**
```json
{
  "podIp": "10.244.0.5",
  "podName": "banking-good-7d8f9c5b6-abc12"
}
```

**Sử dụng:**
- Debug và troubleshooting
- Xác định pod nào đang xử lý request
- Test traffic routing

---

## Test Endpoints

### Test Graceful Shutdown

**Scenario 1: Test /api/drain**
```bash
# Terminal 1: Gửi request deposit (10s)
curl -X POST http://localhost:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001","amount":100000}' &

# Terminal 2: Sau 2s, gọi drain
sleep 2
POD_IP=$(kubectl get pod -l app=banking-good -o jsonpath='{.items[0].status.podIP}')
curl http://$POD_IP:8080/api/drain

# Terminal 3: Kiểm tra readiness
curl http://$POD_IP:8080/actuator/health/readiness
# Expected: {"status":"DOWN"}

# Terminal 4: Thử gửi request mới
curl -X POST http://$POD_IP:8080/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC002","amount":50000}'
# Expected: 503 Service Unavailable
```

**Scenario 2: Test với kubectl delete**
```bash
# Terminal 1: Gửi request
curl -X POST http://localhost:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001","amount":100000}' &

# Terminal 2: Delete pod
kubectl delete pod -l app=banking-good

# Terminal 3: Kiểm tra transaction
curl http://localhost:30081/api/transactions | jq '.[0]'
# Expected: status = "COMPLETED"
```

---

## Error Responses

### 503 Service Unavailable
Pod đang shutdown, không nhận request mới

```json
{
  "error": "Service Unavailable - Shutting down"
}
```

### 400 Bad Request
Tài khoản không tồn tại

```
Account not found: ACC999
```

---

## Endpoint Summary

| Endpoint | Method | Purpose | Used By |
|----------|--------|---------|---------|
| /api/accounts | GET | Lấy danh sách tài khoản | Frontend |
| /api/transactions | GET | Lấy lịch sử giao dịch | Frontend |
| /api/deposit | POST | Nộp tiền (10s) | Frontend |
| /actuator/health/readiness | GET | Readiness check | K8s readinessProbe |
| /actuator/health/liveness | GET | Liveness check | K8s livenessProbe |
| /api/health/ready | GET | Custom readiness | Alternative probe |
| /api/drain | GET | Drain traffic | K8s preStop hook |
| /api/pod-info | GET | Pod information | Debug |

---

## Best Practices

1. **Luôn check readiness** trước khi gửi request
2. **Retry với exponential backoff** khi gặp 503
3. **Monitor /api/drain** để biết khi nào pod đang shutdown
4. **Sử dụng /api/pod-info** để debug traffic routing
5. **Test graceful shutdown** trước khi deploy production
