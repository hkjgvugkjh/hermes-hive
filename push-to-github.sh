#!/bin/bash
# hermes-hive GitHub 推送脚本
# 在 10.10.164.32 上执行

set -e

REPO_DIR="$HOME/workspace/github/hermes-hive"
REPO_NAME="hermes-hive"
GITHUB_USER="hkjgvugkjh"
DESCRIPTION="Hermes Hive - 多服务器 Hermes Studio 管理界面"

echo "=== 进入项目目录 ==="
cd "$REPO_DIR"

echo "=== 初始化 Git 仓库 ==="
if [ -d .git ]; then
  echo "Git 已初始化，跳过"
else
  git init
fi

echo "=== 配置 Git 用户信息 ==="
git config user.name "$GITHUB_USER"
git config user.email "${GITHUB_USER}@users.noreply.github.com"

echo "=== 创建 .gitignore ==="
cat > .gitignore << 'GITIGNORE'
# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
linux/flutter/ephemeral/
windows/flutter/ephemeral/
macos/flutter/ephemeral/
.ephemeral/

# IDE
.idea/
*.iml
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Project specific
.metadata
pubspec.lock
GITIGNORE

echo "=== 检查 GitHub 仓库是否存在 ==="
if gh repo view "$GITHUB_USER/$REPO_NAME" &>/dev/null; then
  echo "仓库已存在，跳过创建"
  # 检查是否已设置 remote
  if git remote get-url origin &>/dev/null; then
    echo "Remote 已设置"
  else
    git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
  fi
else
  echo "=== 创建 GitHub 仓库 ==="
  gh repo create "$GITHUB_USER/$REPO_NAME" \
    --public \
    --description "$DESCRIPTION" \
    --source=. \
    --remote=origin
fi

echo "=== 添加所有文件 ==="
git add -A

echo "=== 提交 ==="
git commit -m "feat: Hermes Hive - Multi-server Hermes Studio management UI

Features:
- Multi-server management for Hermes Studio
- Two connection modes: hermes-proxy / standalone
- i18n support (Chinese / English)
- Markdown rendering for AI messages
- PgUp/PgDn keyboard navigation
- Reverse message loading with lazy load
- Egg of Today: OpenRouter free model combination manager
- Debug log viewer
- Prompt management"

echo "=== 推送至 GitHub ==="
git branch -M main
git push -u origin main

echo "=== 完成 ==="
echo "仓库地址: https://github.com/$GITHUB_USER/$REPO_NAME"
