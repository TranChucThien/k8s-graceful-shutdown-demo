# Test Scripts Documentation

## 📚 Mục Lục

- [📦 Build & Deploy](#-build--deploy)
  - [build-and-push.sh](#build-and-pushsh)
- [🧪 Test Scripts](#-test-scripts)
  - [1. test-concurrent-users.sh](#1-test-concurrent-userssh) - Concurrent traffic test
  - [2. test-deposit.sh](#2-test-depositsh) - Long-running transaction test
  - [3. test-availability.sh](#3-test-availabilitysh) - Simple availability test
  - [4. test-30-deposits.sh](#4-test-30-depositssh) - 30 requests graceful shutdown test
- [🎯 Kịch Bản Test Thực Tế](#-kịch-bản-test-thực-tế)
- [📊 Đọc Kết Quả](#-đọc-kết-quả)
- [🛑 Dừng Test](#-dừng-test)
- [💡 Tips](#-tips)

---

## 📦 Build & Deploy

### build-and-push.sh
Build Docker image và push lên Docker Hub

**Cách dùng:**
```bash
./build-and-push.sh [blue|green]
```

**Ví dụ:**
```bash
# Build blue version
./build-and-push.sh blue

# Build green version
./build-and-push.sh green
```

**Chức năng:**
- Copy file index-{version}.html thành index.html
- Build Docker image với tag chucthien03/banking-demo:{version}
- Push image lên Docker Hub

---

## 🧪 Test Scripts

### 1. 2-test-concurrent-users.sh
**Mục đích:** Gửi nhiều request đồng thời từ nhiều users để test concurrent traffic (chạy liên tục cho đến khi nhấn Ctrl+C)

**Cách dùng:**
```bash
./test-concurrent-users.sh [URL] [USERS] [INTERVAL]
```

**Tham số:**
- `URL`: Service URL (default: http://localhost:30081)
- `USERS`: Số lượng users đồng thời (default: 5)
- `INTERVAL`: Thời gian chờ giữa các request của mỗi user (default: 0.5s)

**Ví dụ:**
```bash
# Test với 10 users, mỗi user gửi request mỗi 0.5s
./test-concurrent-users.sh http://localhost:30081 10 0.5

# Test với 20 users, interval 0.2s (tải cao)
./test-concurrent-users.sh http://localhost:30081 20 0.2
```

**Output:**
```
[2024-01-29 10:30:00] User#1 ✅ SUCCESS - TX#123 - ACC001 - 10.234s
[2024-01-29 10:30:00] User#2 ✅ SUCCESS - TX#124 - ACC002 - 10.156s
[2024-01-29 10:30:01] User#3 ❌ FAILED - HTTP 503
```

**Khi nào dùng:**
- Test rolling update với nhiều users
- Test graceful shutdown với concurrent traffic
- Stress test

---

### 2. 3-test-deposit.sh
**Mục đích:** Gửi liên tục deposit requests (10s mỗi transaction) để test graceful shutdown (chạy liên tục cho đến khi nhấn Ctrl+C)

**Cách dùng:**
```bash
./3-test-deposit.sh [URL] [INTERVAL] [ACCOUNT]
```

**Tham số:**
- `URL`: Service URL (default: http://localhost:30081)
- `INTERVAL`: Thời gian chờ giữa các request (default: 2s)
- `ACCOUNT`: Tài khoản test (default: ACC001)

**Ví dụ:**
```bash
# Gửi deposit mỗi 2s
./3-test-deposit.sh http://localhost:30081 2 ACC001

# Gửi deposit mỗi 0.5s (tải cao)
./3-test-deposit.sh http://localhost:30081 0.5 ACC002
```

**Output:**
```
[2024-01-29 10:30:00] 🔄 Sending deposit request: 3000 VND...
[2024-01-29 10:30:10] ✅ SUCCESS - TX#125 - 10.234s - Total: 10 | Success: 9 | Failed: 0 | Timeout: 1
```

**Khi nào dùng:**
- Test graceful shutdown với long-running transactions
- Verify transaction không bị mất khi delete pod
- Test rolling update với deposit requests

---

### 3. 4-test-availability.sh
**Mục đích:** Gửi liên tục GET requests đơn giản để test availability (chạy liên tục cho đến khi nhấn Ctrl+C)

**Cách dùng:**
```bash
./4-test-availability.sh [URL] [INTERVAL]
```

**Tham số:**
- `URL`: Service URL (default: http://localhost:30081)
- `INTERVAL`: Thời gian chờ giữa các request (default: 1s)

**Ví dụ:**
```bash
# Gửi request mỗi 1s
./4-test-availability.sh http://localhost:30081 1

# Gửi request mỗi 0.1s (tải rất cao)
./4-test-availability.sh http://localhost:30081 0.1
```

**Output:**
```
[2024-01-29 10:30:00] ✅ SUCCESS - HTTP 200 - 0.045s - Total: 100 | Success: 100 | Failed: 0 | Timeout: 0
```

**Khi nào dùng:**
- Test rolling update với simple requests
- Monitor availability
- Quick health check

---

### 4. test-30-deposits.sh
**Mục đích:** Test graceful shutdown với 30 requests được gửi mỗi giây, scale down pod sau request thứ N

**Cách dùng:**
```bash
./test-30-deposits.sh [URL] [DEPLOYMENT] [SCALE_AT]
```

**Tham số:**
- `URL`: Service URL (default: http://localhost:30081)
- `DEPLOYMENT`: Deployment name (default: banking-good)
- `SCALE_AT`: Scale down sau request thứ mấy (default: 5)

**Ví dụ:**
```bash
# Scale down sau request thứ 5
./test-30-deposits.sh http://localhost:30081 banking-good 5

# Scale down sau request thứ 10
./test-30-deposits.sh http://localhost:30081 banking-good 10
```

**Output:**
```
🧪 Test 30 Concurrent Deposits - Auto Scale Down
====================================================
Base URL: http://localhost:30081
Deployment: banking-good
Scale down sau request thứ: 5

📊 Transaction count TRƯỚC test: 128 transactions

[07:50:40.231] Request 1/30 - Sending...
[07:50:41.240] Request 2/30 - Sending...
...
[07:50:44.761] ❌ SCALING DOWN TO 0
...

📈 Kết quả (từ logs vì service down):
   Trước:    128 transactions
   Sau:      Không thể kiểm tra (service scaled to 0)
   Success:  25/30 ✅ (từ HTTP 200 trong log)
   Failed:   5/30 ❌

📋 Phân tích chi tiết (từ log):
   HTTP 200 (Success):       25
   HTTP 000 (Failed):        5
   HTTP 503 (Unavailable):   0
```

**Khi nào dùng:**
- Test graceful shutdown với timing chính xác
- Verify số lượng transactions thành công khi scale down
- Phân tích preStop hook behavior
- So sánh `sleep 20` vs `/api/drain`

**Chi tiết:** Xem [TEST-SCENARIO-30-REQUESTS.md](../TEST-SCENARIO-30-REQUESTS.md) để hiểu rõ timeline và phân tích kết quả

---

## 🎯 Kịch Bản Test Thực Tế

### Scenario 1: Test Graceful Shutdown (Continuous Traffic)
```bash
# Terminal 1: Gửi traffic liên tục
./3-test-deposit.sh http://localhost:30081 0.5

# Terminal 2: Delete pod
kubectl delete pod -l app=banking-good

# Kết quả mong đợi: 100% success, không có failed
```

### Scenario 1b: Test Graceful Shutdown (30 Requests)
```bash
# Chạy test tự động với 30 requests
./test-30-deposits.sh http://localhost:30081 banking-good 5

# Kết quả mong đợi:
# - Với sleep 20: 24-26/30 success (80-87%)
# - Với /api/drain: 5/30 success (17%)
# Chi tiết: TEST-SCENARIO-30-REQUESTS.md
```

### Scenario 2: Test Rolling Update
```bash
# Terminal 1: Gửi traffic với nhiều users
./2-test-concurrent-users.sh http://localhost:30081 10 0.5

# Terminal 2: Rolling update
kubectl set image deployment/banking-good banking=chucthien03/banking-demo:green
kubectl rollout status deployment/banking-good

# Kết quả mong đợi: 100% success, zero downtime
```

### Scenario 3: Test High Load
```bash
# Terminal 1: 20 users, interval 0.2s
./2-test-concurrent-users.sh http://localhost:30081 20 0.2

# Terminal 2: Scale down
kubectl scale deployment/banking-good --replicas=1

# Kết quả mong đợi: Tất cả transactions hoàn thành
```

### Scenario 4: Test Availability During Update
```bash
# Terminal 1: Monitor availability
./4-test-availability.sh http://localhost:30081 0.5

# Terminal 2: Rolling update
kubectl rollout restart deployment/banking-good

# Kết quả mong đợi: 100% success, zero downtime
```

---

## 📊 Đọc Kết Quả

Tất cả scripts đều hiển thị real-time metrics:

- **Total**: Tổng số requests đã gửi
- **Success**: Số requests thành công (HTTP 200)
- **Failed**: Số requests thất bại (HTTP 4xx, 5xx)
- **Timeout**: Số requests timeout (> 15s)

**Success Rate = Success / Total * 100%**

**Mục tiêu:** Success Rate = 100% trong mọi trường hợp

---

## 🛑 Dừng Test

Nhấn **Ctrl+C** để dừng script và xem kết quả tổng hợp:

```
📊 Final Results:
Total Requests: 100
✅ Success: 98 (98%)
❌ Failed: 1 (1%)
⏱️  Timeout: 1 (1%)
```

---

## 💡 Tips

1. **Chạy script trước khi test:** Đảm bảo traffic đang chạy trước khi delete pod hoặc rolling update
2. **Monitor logs:** Mở terminal khác để xem pod logs: `kubectl logs -f -l app=banking-good`
3. **Watch pods:** Monitor pod status: `kubectl get pods -w`
4. **Adjust interval:** Giảm interval để tăng tải, tăng interval để giảm tải
5. **Multiple terminals:** Chạy nhiều scripts cùng lúc để test phức tạp hơn
