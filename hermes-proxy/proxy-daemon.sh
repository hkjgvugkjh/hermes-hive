#!/bin/bash
# hermes-proxy 常驻守护脚本
# 用途：确保 hermes-proxy 始终运行，崩溃/退出后自动重启
# 后台运行：nohup /home/tomac/.hermes/workspace/hermes-application/hermes-hive/hermes-proxy/proxy-daemon.sh &

PROXY_DIR="/home/tomac/.hermes/workspace/hermes-application/hermes-hive/hermes-proxy"
PROXY_BIN="$PROXY_DIR/hermes-proxy-final"
LOG="/tmp/proxy.log"

cd "$PROXY_DIR" || exit 1

while true; do
    # 检查是否已有实例在跑（精确匹配进程，避免误杀自己）
    if ! pgrep -f "^$PROXY_BIN" > /dev/null 2>&1; then
        echo "[$(date '+%F %T')] [daemon] starting hermes-proxy..." >> "$LOG"
        "$PROXY_BIN" -config config.json -admin :8650 >> "$LOG" 2>&1
        echo "[$(date '+%F %T')] [daemon] hermes-proxy exited (code $?), restart in 3s" >> "$LOG"
    fi
    sleep 3
done
