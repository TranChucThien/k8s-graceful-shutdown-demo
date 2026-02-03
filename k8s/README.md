# Kubernetes Manifests

## Deployments

- `k8s-good-blue.yaml` - Blue version với graceful shutdown
- `k8s-good-green.yaml` - Green version với graceful shutdown  
- `k8s-bad.yaml` - Bad version không có graceful shutdown

## Deploy

```bash
kubectl apply -f k8s-good-green.yaml
```

## Rolling Update

```bash
kubectl apply -f k8s-good-blue.yaml
```
