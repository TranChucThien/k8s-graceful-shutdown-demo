#!/bin/bash

# MÔ TẢ: Monitor pod info liên tục để xem request đang được xử lý bởi pod nào
# Dùng để verify traffic routing và load balancing
#
# CÁCH DÙNG:
# ./1-pod-info.sh [URL]
#
# VÍ DỤ:
# ./1-pod-info.sh http://localhost:30081
# ./1-pod-info.sh http://192.168.10.142:30081
#
# Nhấn Ctrl+C để dừng
# ============================================

URL=${1:-http://192.168.10.142:30081}

while true; do
  curl -s $URL/api/pod-info
  echo
  sleep 1
done
