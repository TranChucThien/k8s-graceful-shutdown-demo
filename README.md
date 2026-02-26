# 🏦 Banking Demo - Kubernetes Graceful Shutdown

Demo ứng dụng Spring Boot minh họa sự khác biệt giữa **Graceful Shutdown** và **Immediate Shutdown** trong Kubernetes.

## 📋 Mục Đích

- ✅ **GOOD version**: Transaction hoàn thành ngay cả khi pod bị xóa
- ❌ **BAD version**: Transaction bị hủy khi pod bị xóa, mất dữ liệu

## 🏗️ Kiến Trúc

```
Frontend (HTML/JS) → Spring Boot API (10s transaction) → MySQL 8.0
```

**Tech Stack:** Spring Boot 3.2.0, Java 17, MySQL 8.0, Kubernetes

## 📁 Cấu Trúc Project

```
k8s-graceful-shutdown-demo/
├── app/                    # Spring Boot source code
│   ├── src/main/java/com/example/banking/
│   │   ├── controller/     # REST API endpoints
│   │   ├── service/        # Business logic (10s transaction)
│   │   ├── filter/         # ShutdownFilter (chặn request mới)
│   │   └── ShutdownListener.java  # Graceful shutdown handler
│   └── src/main/resources/
│       ├── application.properties  # Graceful shutdown config
│       └── application-bad.properties  # Immediate shutdown config
├── k8s/                    # Kubernetes manifests
│   ├── k8s-bad.yaml        # ❌ Immediate shutdown
│   ├── k8s-good-blue.yaml  # ✅ Graceful shutdown (blue)
│   ├── k8s-good-green.yaml # ✅ Graceful shutdown (green)
│   └── k8s-unhappy.yaml    # ⚠️ Test configuration
├── database/               # MySQL setup
├── scripts/                # Test scripts
│   ├── 1-pod-info.sh       # Pod information
│   ├── 2-test-concurrent-users.sh  # Concurrent traffic test
│   ├── 3-test-deposit.sh   # Long-running transaction test
│   ├── 4-test-availability.sh      # Availability test
│   └── test-30-deposits.sh # 30 requests graceful shutdown test
├── API-ENDPOINTS.md        # API documentation
└── TEST-SCENARIO-30-REQUESTS.md    # Test scenario analysis
```

## 🚀 Quick Start

### 1. Khởi động MySQL
```bash
cd database
docker-compose up -d
```

### 2. Build & Deploy
```bash
cd scripts
./build-and-push.sh green

cd ../k8s
kubectl apply -f k8s-good-green.yaml
```

### 3. Truy cập
- **GOOD version**: http://localhost:30081
- **BAD version**: http://localhost:30082

## 🔍 So Sánh Cấu Hình

### ❌ BAD Configuration

**application-bad.properties:**
```properties
server.shutdown=immediate
spring.lifecycle.timeout-per-shutdown-phase=0s
```

**k8s-bad.yaml:**
```yaml
spec:
  replicas: 1
  # ❌ Không có readinessProbe
  # ❌ Không có livenessProbe
  # ❌ Không có preStop hook
  # ❌ Không có terminationGracePeriodSeconds
```

**Hậu quả:** Transaction bị hủy, mất dữ liệu

---

### ✅ GOOD Configuration

**application.properties:**
```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

**k8s-good.yaml:**
```yaml
spec:
  replicas: 2
  strategy:
    rollingUpdate:
      maxUnavailable: 0
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: banking
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
        lifecycle:
          preStop:
            httpGet:
              path: /api/drain
              port: 8080
```

**Lợi ích:** Transaction hoàn thành, zero downtime

## 🔌 API Endpoints

| Endpoint | Method | Mô tả |
|----------|--------|-------|
| `/api/accounts` | GET | Danh sách tài khoản |
| `/api/transactions` | GET | Lịch sử giao dịch |
| `/api/deposit` | POST | Nộp tiền (10s) |
| `/api/drain` | GET | PreStop hook - ngăn traffic mới |
| `/actuator/health/readiness` | GET | Readiness probe |
| `/actuator/health/liveness` | GET | Liveness probe |

Chi tiết: [API-ENDPOINTS.md](API-ENDPOINTS.md)

## 🧪 Test Scenarios

**Test Scripts:** Chi tiết đầy đủ tại [scripts/README.md](scripts/README.md)

**Quick Overview:**
- `2-test-concurrent-users.sh` - Test với nhiều users đồng thời (chạy liên tục)
- `3-test-deposit.sh` - Test long-running transactions (chạy liên tục)
- `4-test-availability.sh` - Monitor availability (chạy liên tục)
- `test-30-deposits.sh` - Test graceful shutdown với 30 requests (chạy 1 lần)

**Kịch bản chi tiết:** [TEST-SCENARIO-30-REQUESTS.md](TEST-SCENARIO-30-REQUESTS.md) - Phân tích timeline và kết quả test với 30 requests

### Test 1: BAD Version (Mất Giao Dịch)

```bash
# Đếm số transaction hiện tại
curl -s http://localhost:30082/api/transactions | jq 'length'
# Output: 69

# Terminal 1: Tạo deposit (mất 10s để xử lý)
curl -X POST http://localhost:30082/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber": "ACC001", "amount": 50000}' &

# Terminal 2: Delete pod NGAY LẬP TỨC (trong vòng 10s)
kubectl delete pod -l app=banking-bad --force --grace-period=0

# Kiểm tra lại số transaction
curl -s http://localhost:30082/api/transactions | jq 'length'
# Output: 69 (không tăng - transaction bị mất!)
```

**Kết quả:** ❌ Transaction bị mất hoàn toàn, không được lưu vào database

---

### Test 2: GOOD Version (Giao Dịch An Toàn)

```bash
# Đếm số transaction hiện tại
curl -s http://localhost:30081/api/transactions | jq 'length'
# Output: 69

# Terminal 1: Tạo deposit (mất 10s để xử lý)
curl -X POST http://localhost:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber": "ACC001", "amount": 50000}' &

# Terminal 2: Delete pod NGAY LẬP TỨC (trong vòng 10s)
kubectl delete pod -l app=banking-good

# Đợi pod terminate xong, kiểm tra lại
curl -s http://localhost:30081/api/transactions | jq 'length'
# Output: 70 (tăng lên - transaction được lưu!)

# Xem transaction vừa tạo
curl -s http://localhost:30081/api/transactions | jq '.[0]'
# Output: {"id": 70, "status": "COMPLETED", "amount": 50000}
```

**Kết quả:** ✅ Transaction hoàn thành và được lưu với status COMPLETED

**Lưu ý:** Do `@Transactional`, transaction chỉ commit khi hoàn thành. Bạn sẽ không thấy trạng thái PROCESSING qua API - chỉ thấy COMPLETED (thành công) hoặc không thấy gì (bị mất).

---

### Test 3: Graceful Shutdown với 30 Requests

```bash
# Test tự động: gửi 30 requests, scale down sau request thứ 5
cd scripts
./test-30-deposits.sh http://localhost:30081 banking-good 5
```

**Kết quả với `sleep 20` preStop:**
- ✅ 24-26/30 transactions thành công (80-87%)
- ❌ 4-6/30 transactions thất bại
- Requests 1-5: Thành công (trước scale down)
- Requests 6-25/26: Thành công (trong grace period window)
- Requests 26/27-30: Thất bại (sau khi SIGTERM)

**Chi tiết phân tích:** [TEST-SCENARIO-30-REQUESTS.md](TEST-SCENARIO-30-REQUESTS.md)

---

### Test 4: Rolling Update (Zero Downtime)

```bash
# Terminal 1: Gửi traffic với nhiều users
cd scripts
./2-test-concurrent-users.sh http://localhost:30081 10 0.5

# Terminal 2: Rolling update
kubectl rollout restart deployment banking-good
kubectl get pods -w
```

**Kết quả:** ✅ 100% success, không có downtime

## 🔄 Luồng Graceful Shutdown

```
1. User gửi request → Transaction bắt đầu (10s)
2. kubectl delete pod → Kubernetes gọi preStop hook
3. preStop: GET /api/drain → ShutdownListener.setNotReady()
4. Readiness probe fail → Service ngừng route traffic
5. ShutdownFilter chặn request mới → return 503
6. Transaction đang xử lý tiếp tục hoàn thành
7. SIGTERM → Spring Boot graceful shutdown
8. Transaction completed → Pod terminate
```

**Timeline:**
```
0s:  Transaction start
2s:  kubectl delete pod
2s:  /api/drain called → ready = false
2s:  Service stops routing
10s: Transaction completed ✅
12s: Pod terminated
```

## 🛡️ Các Cơ Chế Bảo Vệ

1. **terminationGracePeriodSeconds: 60** - Chờ 60s trước SIGKILL
2. **preStop: httpGet /api/drain** - Ngăn traffic mới ngay lập tức
3. **server.shutdown=graceful** - Spring Boot chờ request hoàn thành
4. **ShutdownFilter** - Chặn request mới khi draining (503)
5. **readinessProbe** - K8s biết khi nào pod sẵn sàng
6. **maxUnavailable: 0** - Zero downtime deployment

## 📊 Key Takeaways

| | BAD | GOOD |
|---|-----|------|
| Transaction | ❌ Bị hủy | ✅ Hoàn thành |
| Dữ liệu | ❌ Mất | ✅ An toàn |
| Downtime | ❌ Có | ✅ Không |
| Production | ❌ Không dùng | ✅ Khuyến nghị |

## 📝 Best Practices

1. ✅ Luôn enable graceful shutdown trong production
2. ✅ Set terminationGracePeriodSeconds > longest transaction time
3. ✅ Implement readiness + liveness probes
4. ✅ Use preStop hook để drain traffic
5. ✅ Set maxUnavailable: 0 cho zero downtime
6. ✅ Test graceful shutdown trước khi deploy
7. ✅ Monitor shutdown logs

## 🐛 Troubleshooting

**Pod bị killed trước khi transaction hoàn thành:**
```yaml
terminationGracePeriodSeconds: 60  # Tăng lên
```

**Transaction vẫn bị hủy:**
```properties
spring.lifecycle.timeout-per-shutdown-phase=30s  # Tăng lên
```

**Request vẫn vào pod đang shutdown:**
```yaml
lifecycle:
  preStop:
    httpGet:
      path: /api/drain
      port: 8080
```

## 📚 Tài Liệu Thêm

- [API-ENDPOINTS.md](API-ENDPOINTS.md) - Chi tiết API endpoints
- [scripts/README.md](scripts/README.md) - Hướng dẫn test scripts
- [TEST-SCENARIO-30-REQUESTS.md](TEST-SCENARIO-30-REQUESTS.md) - Phân tích chi tiết test 30 requests
- [SHUTDOWN-SCENARIOS.md](SHUTDOWN-SCENARIOS.md) - Các kịch bản shutdown
- [DRAIN-CONTRACT-VERIFICATION.md](DRAIN-CONTRACT-VERIFICATION.md) - Verification tests

## 📧 Contact

Nếu có câu hỏi, vui lòng tạo issue.

---

**Happy Testing! 🚀**
