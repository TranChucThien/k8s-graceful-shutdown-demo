# Kịch Bản Shutdown An Toàn - Banking Demo

## 1. Rolling Update (Khuyến nghị)
**Mục đích:** Update version mới mà không downtime

### Cấu hình quan trọng:
```yaml
spec:
  replicas: 3  # Tối thiểu 2 replicas
  strategy:
    rollingUpdate:
      maxUnavailable: 0  # Không cho phép pod nào unavailable
      maxSurge: 1        # Tạo 1 pod mới trước khi xóa pod cũ
  
  terminationGracePeriodSeconds: 60  # Thời gian chờ pod shutdown
  
  readinessProbe:
    httpGet:
      path: /actuator/health/readiness
      port: 8080
    initialDelaySeconds: 10
    periodSeconds: 5
  
  lifecycle:
    preStop:
      httpGet:
        path: /api/drain
        port: 8080
      # exec:
      #   command: ["sh", "-c", "sleep 20"]  # Chờ request đang xử lý
```

### Các bước thực hiện:
```bash
# 1. Chạy test concurrent users
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.5

# 2. Terminal khác: Rolling update
kubectl set image deployment/banking-good banking=chucthien03/banking-demo:green

# 3. Theo dõi
kubectl rollout status deployment/banking-good
kubectl get pods -w

# Kết quả mong đợi: 100% success, 0% failed/timeout
```

---

## 2. Scale Down An Toàn
**Mục đích:** Giảm số lượng pods khi tải thấp

### Các bước:
```bash
# 1. Chạy test
./test-concurrent-users.sh http://192.168.10.142:30081 5 1

# 2. Scale down từ 3 -> 1
kubectl scale deployment/banking-good --replicas=1

# 3. Kiểm tra
kubectl get pods -w

# Kết quả: Pods cũ chờ 60s để hoàn thành request trước khi terminate
```

---

## 3. Drain Node (Bảo trì node)
**Mục đích:** Di chuyển pods sang node khác để bảo trì

### Các bước:
```bash
# 1. Chạy test
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.5

# 2. Xem pods đang chạy trên node nào
kubectl get pods -o wide

# 3. Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 4. Pods sẽ được tạo lại trên node khác
kubectl get pods -o wide

# 5. Sau khi bảo trì xong, uncordon node
kubectl uncordon <node-name>

# Kết quả: Không có request bị failed
```

---

## 4. Delete Pod (Restart pod)
**Mục đích:** Restart pod khi có vấn đề

### Các bước:
```bash
# 1. Chạy test
./test-concurrent-users.sh http://192.168.10.142:30081 5 1

# 2. Xóa 1 pod
kubectl delete pod <pod-name>

# 3. K8s tự động tạo pod mới
kubectl get pods -w

# Kết quả: Các pods khác vẫn xử lý request, không downtime
```

---

## 5. Graceful Shutdown Toàn Bộ Service
**Mục đích:** Tắt service hoàn toàn

### Các bước:
```bash
# 1. Scale down về 0
kubectl scale deployment/banking-good --replicas=0

# 2. Hoặc delete deployment
kubectl delete deployment banking-good

# 3. Delete service
kubectl delete service banking-good

# Lưu ý: Đảm bảo không còn request đang xử lý
```

---

## 6. Test Các Kịch Bản

### Test 1: Rolling Update với tải cao
```bash
# Terminal 1: 20 users, request mỗi 0.2s
./test-concurrent-users.sh http://192.168.10.142:30081 20 0.2

# Terminal 2: Rolling update
kubectl set image deployment/banking-good banking=chucthien03/banking-demo:blue

# Mong đợi: 100% success
```

### Test 2: Scale down trong khi có giao dịch dài
```bash
# Terminal 1: Gửi deposit requests (10s mỗi request)
./test-deposit-rolling.sh http://192.168.10.142:30081 0.5

# Terminal 2: Scale down
kubectl scale deployment/banking-good --replicas=1

# Mong đợi: Tất cả giao dịch 10s đều hoàn thành
```

### Test 3: Delete pod ngẫu nhiên
```bash
# Terminal 1: Test liên tục
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.5

# Terminal 2: Xóa pod ngẫu nhiên mỗi 30s
while true; do
  POD=$(kubectl get pods -l app=banking-good -o name | shuf -n 1)
  echo "Deleting $POD"
  kubectl delete $POD
  sleep 30
done

# Mong đợi: Không có downtime
```

---

## 7. Các Chỉ Số Quan Trọng

### Cấu hình tối ưu:
- **replicas:** ≥ 2 (production: ≥ 3)
- **maxUnavailable:** 0
- **terminationGracePeriodSeconds:** 60 (hoặc > thời gian xử lý request dài nhất)
- **preStop:** httpGet /api/drain (để ngăn nhận connection mới)
<!-- - **preStop sleep:** 20s (chờ load balancer cập nhật) -->
- **readinessProbe:** Bắt buộc phải có

### Kết quả mong đợi:
- ✅ Success rate: 100%
- ✅ Failed rate: 0%
- ✅ Timeout rate: 0%
- ✅ Không có giao dịch bị mất
- ✅ Không có downtime

---

## 8. So Sánh: Good vs Bad Configuration

### Bad Configuration (k8s-bad.yaml):
```yaml
replicas: 1  # Chỉ 1 pod -> downtime khi update
strategy:
  type: Recreate  # Xóa pod cũ trước -> downtime
# Không có readinessProbe -> nhận traffic ngay khi start
# Không có preStop -> terminate ngay lập tức
```

### Good Configuration (k8s-good.yaml):
```yaml
replicas: 3  # Nhiều pods -> high availability
strategy:
  rollingUpdate:
    maxUnavailable: 0  # Zero downtime
readinessProbe: ...  # Chỉ nhận traffic khi ready
lifecycle:
  preStop:
    httpGet:
      path: /api/drain  # Graceful shutdown
      port: 8080
```

### Test so sánh:
```bash
# Test bad config
kubectl apply -f k8s-bad.yaml
./test-concurrent-users.sh http://192.168.10.142:30082 10 0.5
kubectl set image deployment/banking-bad banking=chucthien03/banking-demo:green
# Kết quả: Có failed/timeout requests

# Test good config
kubectl apply -f k8s-good.yaml
./test-concurrent-users.sh http://192.168.10.142:30081 10 0.5
kubectl set image deployment/banking-good banking=chucthien03/banking-demo:green
# Kết quả: 100% success
```
