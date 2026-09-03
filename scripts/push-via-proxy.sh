#!/bin/bash
# hermes-hive GitHub 推送脚本（通过 SOCKS5 代理）
# 在 10.10.164.32 上执行

set -e

REPO_DIR="$HOME/workspace/github/hermes-hive"
REPO_NAME="hermes-hive"
GITHUB_USER="hkjgvugkjh"
GITHUB_TOKEN="$(gh auth token)"
PROXY="socks5://10.10.164.50:31288"
REMOTE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "=== 进入项目目录 ==="
cd "$REPO_DIR"

echo "=== 配置 SOCKS5 代理 ==="
git config http.proxy "$PROXY"
git config https.proxy "$PROXY"

echo "=== 设置 Remote URL ==="
git remote set-url origin "$REMOTE_URL"

echo "=== 验证远程连接 ==="
timeout 30 git ls-remote origin 2>&1 | head -5

echo "=== 提交本地更改 ==="
git add -A
if git diff --cached --quiet; then
  echo "无新更改需要提交"
else
  git commit -m "update: sync from local"
fi

echo "=== 推送至 GitHub ==="
timeout 120 git push -u origin main

echo "=== 完成 ==="
echo "仓库地址: https://github.com/$GITHUB_USER/$REPO_NAME"
