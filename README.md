# 🏦 Banking Demo - Kubernetes Graceful Shutdown

Demo ứng dụng Spring Boot để minh họa sự khác biệt giữa **Graceful Shutdown** và **Immediate Shutdown** trong Kubernetes.

## 📋 Mục Đích

Chứng minh tầm quan trọng của Graceful Shutdown trong môi trường production:
- ✅ **GOOD version**: Transaction hoàn thành ngay cả khi pod bị xóa
- ❌ **BAD version**: Transaction bị hủy khi pod bị xóa, mất dữ liệu

## 🏗️ Kiến Trúc

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (HTML/JS)                       │
│  - Form nộp tiền (10s processing)                          │
│  - Hiển thị danh sách tài khoản                            │
│  - Lịch sử giao dịch                                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Spring Boot Backend (Java 17)                  │
│  - REST API                                                 │
│  - Transaction processing (10s delay)                       │
│  - Pessimistic locking                                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    MySQL 8.0 Database                       │
│  - accounts table                                           │
│  - transactions table                                       │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Tech Stack

- **Backend**: Spring Boot 3.2.0, Java 17, Spring Data JPA
- **Frontend**: HTML, JavaScript (Vanilla)
- **Database**: MySQL 8.0
- **Container**: Docker, Kubernetes
- **Build**: Maven, Multi-stage Dockerfile

## 📁 Cấu Trúc Project

```
k8s-graceful-shutdown-demo/
├── app/                                 # Application source code
│   ├── src/main/java/com/example/banking/
│   │   ├── BankingApplication.java
│   │   ├── ShutdownListener.java
│   │   ├── controller/
│   │   │   ├── BankingController.java
│   │   │   └── HomeController.java
│   │   ├── service/
│   │   │   └── BankingService.java
│   │   ├── repository/
│   │   │   ├── AccountRepository.java
│   │   │   └── TransactionRepository.java
│   │   ├── entity/
│   │   │   ├── Account.java
│   │   │   └── Transaction.java
│   │   ├── dto/
│   │   │   └── DepositRequest.java
│   │   └── filter/
│   │       └── ShutdownFilter.java
│   ├── src/main/resources/
│   │   ├── application.properties
│   │   ├── application-bad.properties
│   │   └── static/
│   │       ├── index.html
│   │       ├── index-blue.html
│   │       └── index-green.html
│   ├── Dockerfile
│   └── pom.xml
├── database/                            # Database setup
│   ├── docker-compose.yml
│   └── init.sql
├── k8s/                                 # Kubernetes manifests
│   ├── k8s-bad.yaml
│   ├── k8s-good-blue.yaml
│   └── k8s-good-green.yaml
├── scripts/                             # Build & test scripts
│   ├── build-and-push.sh
│   ├── test-concurrent-users.sh
│   ├── test-deposit-rolling.sh
│   ├── test-rolling-update.sh
│   ├── test-traffic-routing.sh
│   └── locustfile.py
├── DRAIN-CONTRACT-VERIFICATION.md
├── SHUTDOWN-SCENARIOS.md
└── README.md
```

## 🚀 Cài Đặt và Chạy

### 1. Khởi động MySQL

```bash
cd database
docker-compose up -d
```

Kiểm tra MySQL đã chạy:
```bash
docker ps | grep mysql
```

### 2. Build Docker Image

```bash
cd scripts
./build-and-push.sh green
```

### 3. Push Image (Optional)

```bash
docker push chucthien03/banking-demo:latest
```

### 4. Deploy lên Kubernetes

```bash
cd k8s

# Deploy BAD version (immediate shutdown)
kubectl apply -f k8s-bad.yaml

# Deploy GOOD version (graceful shutdown)
kubectl apply -f k8s-good-green.yaml
```

### 5. Kiểm tra Pods

```bash
kubectl get pods
kubectl get svc
```

### 6. Truy cập ứng dụng

- **BAD version**: http://localhost:30082
- **GOOD version**: http://localhost:30081

## 🔍 So Sánh Cấu Hình

### ❌ BAD Configuration (Immediate Shutdown)

**application-bad.properties:**
```properties
server.shutdown=immediate
spring.lifecycle.timeout-per-shutdown-phase=0s
```

**k8s-bad.yaml:**
```yaml
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: banking
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "bad"
        # ❌ KHÔNG có readinessProbe
        # ❌ KHÔNG có livenessProbe
        # ❌ KHÔNG có preStop hook
        # ❌ KHÔNG có terminationGracePeriodSeconds
```

**Hậu quả:**
- Pod nhận SIGTERM → Dừng ngay lập tức
- Transaction đang xử lý bị hủy
- Dữ liệu bị mất
- Trải nghiệm người dùng tệ

---

### ✅ GOOD Configuration (Graceful Shutdown)

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
      maxUnavailable: 0  # ✅ Không cho phép downtime
  template:
    spec:
      terminationGracePeriodSeconds: 60  # ✅ Cho 60s để cleanup
      containers:
      - name: banking
        readinessProbe:  # ✅ Kiểm tra sẵn sàng nhận traffic
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:  # ✅ Kiểm tra pod còn sống
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        lifecycle:
          preStop:  # ✅ Gọi /api/drain để ngăn nhận connection mới
            httpGet:
              path: /api/drain
              port: 8080
```

**Lợi ích:**
- Pod nhận SIGTERM → Chờ hoàn thành transaction
- Dữ liệu được bảo toàn
- Zero downtime deployment
- Trải nghiệm người dùng tốt

## 🔌 REST API Endpoints

### GET /api/accounts
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

### GET /api/transactions
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

### POST /api/deposit
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

## 🧪 Kịch Bản Test

### Test 1: BAD Version (Mất Dữ Liệu)

**Mục tiêu:** Chứng minh immediate shutdown gây mất dữ liệu

**Các bước:**

1. Truy cập http://localhost:30082
2. Chọn tài khoản (ví dụ: ACC001 - Nguyen Van A)
3. Nhập số tiền: 100000
4. Nhấn nút **"Nộp tiền (10s)"**
5. **NGAY LẬP TỨC** mở terminal và xóa pod:
   ```bash
   kubectl delete pod -l app=banking-bad --force --grace-period=0
   ```

**Kết quả mong đợi:**

```
❌ Transaction bị HỦY
❌ Tiền KHÔNG vào tài khoản
❌ Transaction status = "PROCESSING" (không bao giờ "COMPLETED")
❌ Balance không thay đổi
```

**Log trong pod (trước khi bị kill):**
```
🔵 [START] Deposit transaction for account: ACC001, amount: 100000
📝 [STEP 1] Transaction created with ID: 1, status: PROCESSING
⏳ [STEP 2] Processing transaction... (sleeping 10 seconds)
🛑 SIGTERM RECEIVED - Starting graceful shutdown...
❌ [ERROR] Transaction interrupted
```

---

### Test 2: GOOD Version (Dữ Liệu An Toàn)

**Mục tiêu:** Chứng minh graceful shutdown bảo vệ dữ liệu

**Các bước:**

1. Truy cập http://localhost:30081
2. Chọn tài khoản (ví dụ: ACC002 - Tran Thi B)
3. Nhập số tiền: 200000
4. Nhấn nút **"Nộp tiền (10s)"**
5. **NGAY LẬP TỨC** mở terminal và xóa pod:
   ```bash
   kubectl delete pod -l app=banking-good
   ```

**Kết quả mong đợi:**

```
✅ Transaction HOÀN THÀNH sau 10 giây
✅ Tiền VÀO tài khoản
✅ Transaction status = "COMPLETED"
✅ Balance tăng đúng số tiền
✅ Pod mới được tạo tự động (replicas=2)
```

**Log trong pod:**
```
🔵 [START] Deposit transaction for account: ACC002, amount: 200000
📝 [STEP 1] Transaction created with ID: 2, status: PROCESSING
⏳ [STEP 2] Processing transaction... (sleeping 10 seconds)
🛑 SIGTERM RECEIVED - Starting graceful shutdown...
✅ [STEP 2] Processing completed
🔒 [STEP 3] Acquiring lock on account: ACC002
💰 [STEP 3] Balance updated: 2000000 -> 2200000
✅ [STEP 4] Transaction completed with ID: 2
🟢 [SUCCESS] Deposit transaction completed successfully
🛑 PreDestroy called - Cleaning up resources...
```

---

### Test 3: Rolling Update (Zero Downtime)

**Mục tiêu:** Chứng minh rolling update không gây downtime

**Các bước:**

1. Mở 2 tab browser:
   - Tab 1: http://localhost:30081
   - Tab 2: Terminal để xem pods
2. Trong Tab 1, liên tục gửi request nộp tiền (mỗi 5 giây)
3. Trong Tab 2, trigger rolling update:
   ```bash
   kubectl rollout restart deployment banking-good
   ```
4. Quan sát:
   ```bash
   kubectl get pods -w
   ```

**Kết quả mong đợi:**

```
✅ Tất cả request đều thành công
✅ Không có request nào bị lỗi
✅ Pod cũ chờ hoàn thành transaction trước khi terminate
✅ Pod mới sẵn sàng trước khi pod cũ bị xóa (maxUnavailable=0)
```

---

### Test 4: Stress Test (Multiple Concurrent Requests)

**Mục tiêu:** Test graceful shutdown với nhiều request đồng thời

**Các bước:**

1. Mở 5 tab browser cùng lúc
2. Tất cả tab truy cập http://localhost:30081
3. Đồng thời nhấn "Nộp tiền" trên cả 5 tab
4. Ngay lập tức xóa pod:
   ```bash
   kubectl delete pod -l app=banking-good
   ```

**Kết quả mong đợi:**

```
✅ Tất cả 5 transaction đều hoàn thành
✅ Không có transaction nào bị mất
✅ Balance được cập nhật chính xác
✅ Pessimistic locking hoạt động đúng (không có race condition)
```

## 📊 Giải Thích Chi Tiết

### 🔄 Luồng Graceful Shutdown

```
1. User gửi request → Transaction bắt đầu (status=PROCESSING)
                      ↓
2. Sleep 10s để mô phỏng xử lý chậm
                      ↓
3. kubectl delete pod → Kubernetes gửi SIGTERM
                      ↓
4. preStop hook: sleep 20s (cho Service ngừng route traffic)
                      ↓
5. Spring Boot nhận SIGTERM → Không nhận request mới
                      ↓
6. Spring Boot chờ transaction hiện tại hoàn thành (max 30s)
                      ↓
7. Transaction hoàn thành → Update balance → status=COMPLETED
                      ↓
8. PreDestroy cleanup → Pod terminate
```

### ⏱️ Timeline So Sánh

**BAD Version:**
```
0s:  User nhấn "Nộp tiền"
0s:  Transaction created (status=PROCESSING)
2s:  kubectl delete pod --force
2s:  ❌ Pod killed ngay lập tức
2s:  ❌ Transaction bị hủy
```

**GOOD Version:**
```
0s:  User nhấn "Nộp tiền"
0s:  Transaction created (status=PROCESSING)
2s:  kubectl delete pod
2s:  SIGTERM received
2s:  preStop: httpGet /api/drain
2s:  ShutdownListener.setNotReady() -> ready = false
2s:  Service ngừng route traffic đến pod này
2s:  Spring Boot: Không nhận request mới
2s:  Spring Boot: Chờ transaction hoàn thành
10s: Transaction processing done
10s: Update balance
10s: Transaction status = COMPLETED
10s: ✅ Dữ liệu an toàn
22s: PreDestroy cleanup
22s: Pod terminate
```

### 🛡️ Các Cơ Chế Bảo Vệ

1. **terminationGracePeriodSeconds: 60**
   - Kubernetes chờ tối đa 60s trước khi SIGKILL
   - Đủ thời gian cho transaction 10s + preStop 20s + cleanup

2. **preStop: sleep 20**
   - Cho Service kịp cập nhật endpoint
   - Tránh request mới vào pod đang shutdown

3. **server.shutdown=graceful**
   - Spring Boot không nhận request mới
   - Chờ request hiện tại hoàn thành

4. **spring.lifecycle.timeout-per-shutdown-phase=30s**
   - Chờ tối đa 30s cho mỗi phase shutdown
   - Đủ cho transaction 10s

5. **readinessProbe**
   - Kubernetes biết khi nào pod sẵn sàng
   - Không route traffic đến pod chưa ready

6. **maxUnavailable: 0**
   - Rolling update không cho phép downtime
   - Pod mới ready trước khi pod cũ terminate

## 🎯 Key Takeaways

### ❌ Không Graceful Shutdown:
- Transaction bị hủy giữa chừng
- Dữ liệu không nhất quán
- Trải nghiệm người dùng tệ
- Khó debug và troubleshoot

### ✅ Có Graceful Shutdown:
- Transaction luôn hoàn thành
- Dữ liệu nhất quán
- Zero downtime deployment
- Production-ready

## 📝 Best Practices

1. **Luôn enable graceful shutdown** trong production
2. **Set timeout phù hợp** với longest transaction
3. **Implement health checks** (readiness + liveness)
4. **Use preStop hook** để deregister từ service discovery
5. **Set terminationGracePeriodSeconds** > (longest transaction + preStop)
6. **Test graceful shutdown** trước khi deploy production
7. **Monitor shutdown logs** để phát hiện vấn đề sớm
8. **Use pessimistic locking** cho critical transactions

## 🐛 Troubleshooting

### Pod bị killed trước khi transaction hoàn thành

**Nguyên nhân:** `terminationGracePeriodSeconds` quá ngắn

**Giải pháp:**
```yaml
terminationGracePeriodSeconds: 60  # Tăng lên
```

### Transaction vẫn bị hủy dù có graceful shutdown

**Nguyên nhân:** Spring Boot timeout quá ngắn

**Giải pháp:**
```properties
spring.lifecycle.timeout-per-shutdown-phase=30s  # Tăng lên
```

### Request vẫn vào pod đang shutdown

**Nguyên nhân:** Thiếu preStop hook

**Giải pháp:**
```yaml
lifecycle:
  preStop:
    httpGet:
      path: /api/drain
      port: 8080
```

## 📚 Tài Liệu Tham Khảo

- [Spring Boot Graceful Shutdown](https://docs.spring.io/spring-boot/docs/current/reference/html/web.html#web.graceful-shutdown)
- [Kubernetes Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 📧 Contact

Nếu có câu hỏi, vui lòng tạo issue hoặc liên hệ qua email.

---

**Happy Testing! 🚀**

## 📡 Test Bằng API (curl/Postman)

### Test 5: API Test - BAD Version

**Bước 1:** Gửi request nộp tiền
```bash
curl -X POST http://localhost:30082/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001","amount":100000}' &
```

**Bước 2:** Ngay lập tức xóa pod (trong vòng 2 giây)
```bash
kubectl delete pod -l app=banking-bad --force --grace-period=0
```

**Bước 3:** Kiểm tra kết quả
```bash
# Kiểm tra balance (không thay đổi)
curl http://localhost:30082/api/accounts | jq '.[] | select(.accountNumber=="ACC001")'

# Kiểm tra transaction (status = PROCESSING)
curl http://localhost:30082/api/transactions | jq '.[0]'
```

**Kết quả:**
```json
{
  "id": 1,
  "accountNumber": "ACC001",
  "type": "DEPOSIT",
  "amount": 100000,
  "status": "PROCESSING",
  "createdAt": "2026-01-29T10:30:00"
}
```

---

### Test 6: API Test - GOOD Version

**Bước 1:** Gửi request nộp tiền
```bash
curl -X POST http://localhost:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC002","amount":200000}' &
```

**Bước 2:** Ngay lập tức xóa pod
```bash
kubectl delete pod -l app=banking-good
```

**Bước 3:** Chờ 10 giây rồi kiểm tra
```bash
sleep 10

# Kiểm tra balance (đã tăng)
curl http://localhost:30081/api/accounts | jq '.[] | select(.accountNumber=="ACC002")'

# Kiểm tra transaction (status = COMPLETED)
curl http://localhost:30081/api/transactions | jq '.[0]'
```

**Kết quả:**
```json
{
  "id": 2,
  "accountNumber": "ACC002",
  "type": "DEPOSIT",
  "amount": 200000,
  "status": "COMPLETED",
  "createdAt": "2026-01-29T10:30:00"
}
```

---

### Test 7: Advanced Automated Test Script

**Script tự động test với logic tính toán success/fail:**

File `test-graceful-shutdown.sh` đã được tạo sẵn trong project.

**Tính năng:**
- Test cả BAD và GOOD version
- Gửi 20 concurrent requests
- Tính toán số lượng: Completed, Processing, Failed
- Tính Success Rate (%)
- So sánh balance trước/sau
- Tính tiền bị mất (nếu có)
- Hiển thị kết quả với màu sắc
- So sánh tổng quan 2 version

**Chạy script:**
```bash
chmod +x test-graceful-shutdown.sh
./test-graceful-shutdown.sh
```

**Output mẫu:**
```
╔════════════════════════════════════════════════════════════╗
║     Graceful Shutdown Test - Multiple Transactions        ║
╔════════════════════════════════════════════════════════════╗

🔴 Testing BAD Version (Immediate Shutdown)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Initial Balance: 1000000
📤 Sending 20 concurrent requests...
⏳ Waiting 2s before deleting pod...
🛑 Deleting pod with --force...

📊 BAD Version Results:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📤 Total Requests Sent:      20
📝 Transactions Created:     20
✅ Completed:                3
⏳ Processing (stuck):       17
❌ Failed:                   0
📈 Success Rate:             15%

💰 Initial Balance:          1000000
💰 Final Balance:            1030000
💰 Balance Change:           +30000 (Expected: +30000)
💸 Lost Money:               170000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🟢 Testing GOOD Version (Graceful Shutdown)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Initial Balance: 1000000
📤 Sending 20 concurrent requests...
⏳ Waiting 2s before deleting pod...
🛑 Deleting pod with graceful shutdown...
⏳ Waiting for transactions to complete (15s)...

📊 GOOD Version Results:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📤 Total Requests Sent:      20
📝 Transactions Created:     20
✅ Completed:                20
⏳ Processing:               0
❌ Failed:                   0
📈 Success Rate:             100%

💰 Initial Balance:          1000000
💰 Final Balance:            1200000
💰 Balance Change:           +200000 (Expected: +200000)
✅ Perfect! All transactions completed successfully!

╔════════════════════════════════════════════════════════════╗
║                    Comparison Summary                      ║
╚════════════════════════════════════════════════════════════╝

❌ BAD Version:
   - Immediate shutdown kills transactions
   - Data loss occurs
   - Transactions stuck in PROCESSING state
   - Poor user experience

✅ GOOD Version:
   - Graceful shutdown completes all transactions
   - No data loss
   - All transactions reach COMPLETED state
   - Excellent user experience

✅ Test completed!
```

---

### Test 8: Custom Test Parameters

**Chỉnh sửa script để test với parameters khác:**

```bash
# Mở file test-graceful-shutdown.sh và sửa:
TOTAL_REQUESTS=50        # Số lượng requests
ACCOUNT="ACC002"         # Tài khoản test
AMOUNT=5000              # Số tiền mỗi giao dịch
DELAY_BEFORE_DELETE=3    # Delay trước khi xóa pod (giây)
```

---

### Test 9: Monitor Logs

**Terminal 1:** Gửi request
```bash
curl -X POST http://localhost:30081/api/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountNumber":"ACC001","amount":100000}' &
```

**Terminal 2:** Xem logs
```bash
kubectl logs -f -l app=banking-good
```

**Terminal 3:** Xóa pod
```bash
sleep 2 && kubectl delete pod -l app=banking-good
```

**Logs:**
```
🔵 [START] Deposit transaction for account: ACC001, amount: 100000
📝 [STEP 1] Transaction created with ID: 1, status: PROCESSING
⏳ [STEP 2] Processing transaction... (sleeping 10 seconds)
🛑 SIGTERM RECEIVED - Starting graceful shutdown...
✅ [STEP 2] Processing completed
🔒 [STEP 3] Acquiring lock on account: ACC001
💰 [STEP 3] Balance updated: 1000000 -> 1100000
✅ [STEP 4] Transaction completed with ID: 1
🟢 [SUCCESS] Deposit transaction completed successfully
🛑 PreDestroy called - Cleaning up resources...
```
