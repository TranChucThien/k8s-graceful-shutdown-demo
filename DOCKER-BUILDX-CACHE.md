# 🐳 Docker Buildx - Tối Ưu Build Image với Layer Caching

## 🎯 1. Mục Tiêu

Giải quyết các vấn đề:
- Build image nhanh hơn
- Reuse layer giữa các lần build (kể cả khác máy)
- Giảm thời gian CI/CD
- Hiểu rõ khi nào layer bị thay đổi

---

## 🆕 2. Điểm Mới của Buildx so với Docker Build Truyền Thống

| | `docker build` (legacy) | `docker buildx build` (BuildKit) |
|---|---|---|
| Cache backend | Chỉ local layer cache | Local, inline, registry, S3, GHA... |
| Cross-machine cache | ❌ Không hỗ trợ | ✅ `--cache-from` / `--cache-to` registry |
| Multi-stage cache | Chỉ cache stage cuối | `mode=max` cache **tất cả** intermediate stages |
| Parallel build | Tuần tự từng step | Song song các stage không phụ thuộc nhau |
| Build output | Chỉ lưu local | `--push`, `--load`, `--output` linh hoạt |
| Multi-platform | ❌ | ✅ `--platform linux/amd64,linux/arm64` |

**Tóm lại:** Buildx + BuildKit cho phép **cache layer qua registry**, giúp CI runner mới hoàn toàn vẫn build nhanh nhờ pull cache từ remote — điều `docker build` truyền thống không làm được.

---

## 🧱 3. Nguyên Lý Hoạt Động

```
Docker image = tập hợp các layer (sha256)

Cache hoạt động khi:
  1. Dockerfile instruction giống nhau
  2. Input (file, context) giống nhau
  3. Có nguồn cache (local hoặc registry)
```

### Các loại cache trong Buildx

| Type | Mô tả | Use case |
|------|--------|----------|
| `inline` | Embed cache metadata vào image | Đơn giản, không cần tag riêng |
| `registry` | Lưu cache vào tag riêng trên registry | Production CI/CD (khuyến nghị) |
| `local` | Lưu cache vào thư mục local | Dev machine |
| `gha` | GitHub Actions cache | GitHub CI |
| `s3` | Lưu cache lên S3 | AWS CI/CD |

---

## ⚙️ 4. Setup Môi Trường

### 4.1 Xoá toàn bộ cache (giả lập máy mới)

```bash
docker system prune -a -f
docker builder prune -a -f
```

### 4.2 Tạo builder dùng BuildKit

```bash
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

---

## 🐳 5. Build Lần Đầu (Tạo Cache)

```bash
docker buildx build \
  --push \
  -t chucthien03/banking-demo:inline \
  --cache-to type=inline,mode=max \
  .
```

**Kết quả:**
- ✅ Image được push lên registry
- ✅ Cache metadata được embed vào image (inline cache)

> `mode=max` = cache **tất cả** layer kể cả intermediate stages (không chỉ stage cuối)

---

## 🧪 6. Giả Lập Môi Trường Mới (CI Runner Mới)

```bash
docker system prune -a -f
docker builder prune -a -f
```

Lúc này: **KHÔNG còn cache local** → giống CI runner mới hoàn toàn.

---

## 🚀 7. Build Lại Sử Dụng Cache từ Registry

```bash
docker buildx build \
  --push \
  -t chucthien03/banking-demo:new-tag \
  --cache-from type=registry,ref=chucthien03/banking-demo:inline \
  --cache-to type=inline,mode=max \
  .
```

**Kết quả mong đợi** — các step hiển thị `CACHED`:
- ✅ `mvn dependency:go-offline`
- ✅ Build step
- ✅ Copy layers

---

## ✏️ 8. Thay Đổi Code và Build Lại

```bash
# Thay đổi code
echo "// change code" >> src/main/java/com/example/banking/BankingApplication.java

# Build lại
docker buildx build \
  --push \
  -t chucthien03/banking-demo:new-tag-v2 \
  --cache-from type=registry,ref=chucthien03/banking-demo:inline \
  --cache-to type=inline,mode=max \
  .
```

---

## 🔍 9. Verify Layer Reuse Giữa Các Image

### Pull image về local

```bash
docker pull chucthien03/banking-demo:inline
docker pull chucthien03/banking-demo:new-tag
```

### Inspect layers

```bash
# Image cũ (trước khi thay đổi code)
docker inspect chucthien03/banking-demo:inline | jq '.[0].RootFS.Layers'

# Image mới (sau khi thay đổi code)
docker inspect chucthien03/banking-demo:new-tag | jq '.[0].RootFS.Layers'
```

---

## 📊 10. Phân Tích Kết Quả (Đã Verify Thực Tế)

### Kết quả thực tế

```
Image: inline                          Image: new-tag
─────────────────────────────────────────────────────────────────────
sha256:f2a7f072...b74b6   ✔ SAME       sha256:f2a7f072...b74b6
sha256:2f61c7a4...0fe581  ✔ SAME       sha256:2f61c7a4...0fe581
sha256:7d58b159...96af1   ✔ SAME       sha256:7d58b159...96af1
sha256:f953134c...ffd4f3  ✔ SAME       sha256:f953134c...ffd4f3
sha256:87ee703d...1832be4 ✔ SAME       sha256:87ee703d...1832be4
sha256:fed0cb9e...a26666  ✔ SAME       sha256:fed0cb9e...a26666
sha256:9219a9c0...11444   ✔ SAME       sha256:9219a9c0...11444
sha256:a355be53...150b4   ✔ SAME       sha256:a355be53...150b4
sha256:5f70bf18...c3c6ef  ✔ SAME       sha256:5f70bf18...c3c6ef
sha256:70045526...d7a2    ❌ DIFF       sha256:0467b316...c815
─────────────────────────────────────────────────────────────────────
                          9/10 layers reused = 90% cache hit!
```

### Phân tích

- ✅ **9/10 layers** hoàn toàn giống nhau (cache hit) — bao gồm base image, dependencies, config
- ❌ **1 layer cuối** khác nhau — đây là layer chứa application code đã thay đổi
- 🎯 **Kết luận:** Cache từ registry hoạt động chính xác, chỉ rebuild layer bị ảnh hưởng bởi code change

### Mapping với Dockerfile

```dockerfile
# Layers 1-9: CACHED ✔ (không thay đổi)
FROM eclipse-temurin:17-jre-alpine       # base image layers
COPY pom.xml .
RUN mvn dependency:go-offline            # dependency layer

# Layer 10: REBUILD ❌ (code thay đổi)
COPY src ./src
RUN mvn package                          # → layer mới do src thay đổi
```

---

## 🔥 11. Insights Quan Trọng

- ✅ **Cache hoạt động cross-machine** — không cần cùng máy, chỉ cần `--cache-from` registry
- ✅ **Không cần image giống nhau** — image digest có thể khác nhưng layer vẫn reuse
- ✅ **Tối ưu build** — code thay đổi → chỉ rebuild layer cuối
- ✅ **Parallel stages** — BuildKit build song song các stage độc lập

---

## ⚠️ 12. Các Lỗi Thường Gặp

| Lỗi | Nguyên nhân |
|------|-------------|
| Cache không hoạt động | Không dùng `buildx` (dùng `docker build` legacy) |
| Build lại từ đầu | Thiếu `--cache-from` |
| `Error: No such object` | Chưa `docker pull` image trước khi `inspect` |
| `imagetools inspect` không có layer | Đang inspect manifest index, không phải image |

---

## 🚀 13. Best Practice cho Production CI/CD

### Dùng cache tag riêng (khuyến nghị)

```bash
docker buildx build \
  --push \
  -t app:v1 \
  --cache-from type=registry,ref=app:cache \
  --cache-to type=registry,ref=app:cache,mode=max \
  .
```

**Ưu điểm so với inline cache:**
- ✅ Cache không phụ thuộc vào image tag
- ✅ Reuse tốt hơn khi image tag thay đổi liên tục
- ✅ Phù hợp CI/CD pipeline

### Ví dụ trong GitHub Actions

```yaml
- name: Build and push
  uses: docker/build-push-action@v5
  with:
    push: true
    tags: app:${{ github.sha }}
    cache-from: type=registry,ref=app:cache
    cache-to: type=registry,ref=app:cache,mode=max
```

---

## 🏁 14. Kết Luận

| Điểm | Chi tiết |
|-------|----------|
| Cache dựa trên | Layer sha256 hash |
| Cache source | Registry, local, S3, GHA |
| Cross-machine | ✅ Có (qua registry) |
| Code thay đổi | Chỉ layer cuối bị rebuild |
| Best practice | `--cache-from` registry + Dockerfile tách layer đúng |

> **TL;DR:** Muốn build nhanh → `cache-from` registry + Dockerfile tách dependency/code thành layer riêng.

---

## 📚 Tài Liệu Tham Khảo

- [Docker Buildx docs](https://docs.docker.com/build/buildx/)
- [BuildKit cache backends](https://docs.docker.com/build/cache/backends/)
- [Best practices for Dockerfile](https://docs.docker.com/build/building/best-practices/)
