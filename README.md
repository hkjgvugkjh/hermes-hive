# Hermes Hive 使用说明

## 一、产品简介

Hermes Hive 是 Hermes Studio 的统一管理平台，支持在一个界面中管理多个 Hermes Web UI 服务器，并提供跨服务器协同工作流水线、版本控制、实时仪表板等功能。

## 二、两种连接模式

### 2.1 独立模式（Standalone）

**适用场景：** 服务器在本地网络，可直接访问。

**特点：**
- 手工添加每台服务器
- 直连 Hermes Studio HTTP/WebSocket
- 每台服务器独立配置账号密码

**配置步骤：**
1. 启动后点击右上角 ⚙️ 进入全局配置
2. 选择 "Standalone" 模式
3. 返回主页，点击 "Add Server"
4. 填写：
   - **Server Name：** 显示名称（如 "办公室服务器"）
   - **Server URL：** Hermes Studio 地址（如 `http://192.168.1.100:3000`）
   - **Profile：** 使用的 profile（默认 `default`）
   - **Authentication：** 如服务器需要认证，开启后填写用户名密码
5. 点击 "Test" 测试连接，成功后点击 "Save"

### 2.2 Hermes Proxy 模式

**适用场景：** 服务器在 NAT/防火墙后，通过 hermes-proxy 统一入口。

**特点：**
- 配置代理地址和 Admin Token
- 服务器列表从代理自动获取
- X25519 + ChaCha20-Poly1305 端到端加密
- 单入口管理多台远程服务器

**配置步骤：**
1. 启动后点击右上角 ⚙️ 进入全局配置
2. 选择 "Hermes Proxy" 模式
3. 填写：
   - **Proxy URL：** 代理地址（如 `https://proxy.example.com:8080`）
   - **Admin Token：** 代理管理员令牌
   - **Use Encryption：** 建议开启（WSS 加密）
4. 点击 "Test" 测试代理连通性
5. 点击 "Save" 保存
6. 返回主页，点击 "Fetch from Proxy" 获取服务器列表

## 三、服务器操作

### 双击连接服务器
在左侧服务器列表中，**单击**服务器名称即可选中并连接。选中后右侧显示：
- 会话列表（Sessions 面板）
- 聊天输入框

### 新建会话
点击 Sessions 面板右上角的 **+** 按钮。

### 切换会话
在左侧 Sessions 列表中单击会话名称。

### 删除会话
点击会话右侧的 **⋮** 菜单，选择 "Delete"。

### 编辑服务器
点击服务器右侧的 **⋮** 菜单，选择 "Edit"。

### 删除服务器
点击服务器右侧的 **⋮** 菜单，选择 "Delete"。

## 四、聊天功能

1. 选中服务器后，在底部输入框输入消息
2. 按 Enter 或点击发送按钮发送
3. 支持多轮对话，自动关联会话
4. 用户消息显示在右侧（紫色），AI 回复显示在左侧
5. **自动续聊模式：** 点击工具栏 🔄 图标启用，AI 完成每个子任务后回复 OK 继续，全部完成回复 DONE 停止

## 五、协同工作（跨服务器流水线）

### 5.1 功能概述

协同工作模块支持大型项目的任务划分、跨服务器分发、流水线/并行执行，实现多服务器协同开发。

**入口：** 工具栏点击 🌳 "协同工作" 按钮

### 5.2 项目管理

1. **创建项目：** 点击"新建项目"，填写名称、描述、仓库地址
2. **选择项目：** 点击项目卡片切换当前工作项目
3. **删除项目：** 点击项目右侧菜单删除

### 5.3 创建流水线

**方式一：智能分析创建**
1. 选择项目后，点击"智能创建"
2. 填写流水线名称
3. 输入项目需求（每行一条）
4. 系统自动分析生成流水线阶段和任务

**方式二：模板创建**
1. 点击"从模板"
2. 选择模板类型：
   - **全栈项目开发：** 需求分析 → 设计 → 开发 → 测试 → 部署
   - **CI/CD 流水线：** 检出 → 构建 → 测试 → 部署
   - **代码审查：** 静态分析 → 人工审查 → 修复

### 5.4 执行模式

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **串行** | 阶段内任务依次执行 | 有依赖关系的任务链 |
| **并行** | 阶段内所有任务同时执行 | 无依赖的独立任务 |

点击流水线上的"切并行/切串行"按钮切换。

### 5.5 执行控制

- **▶ 执行：** 开始运行流水线
- **⏸ 暂停：** 暂停当前执行（下一任务开始前生效）
- **▶ 恢复：** 从暂停处继续执行
- **⏹ 取消：** 终止整个流水线
- **🔄 重置：** 重置所有任务状态为待执行

### 5.6 查看日志

点击"日志"标签页查看执行历史，每条日志显示时间、级别（info/success/warn/错误）、消息内容。

## 六、版本控制

### 6.1 Git 操作

**入口：** 工具栏点击 📦 "版本控制" 按钮

**支持的操作：**
- 克隆仓库（Clone）
- 检出分支（Checkout，支持创建新分支）
- 提交更改（Commit）
- 推送（Push）
- 拉取（Pull）
- 查看状态（Status）
- 查看日志（Log）
- 查看差异（Diff）
- 合并分支（Merge）
- 冲突检测（Detect Conflicts）

### 6.2 SVN 操作

- 检出（Checkout）
- 更新（Update）
- 提交（Commit）
- 查看状态（Status）
- 查看日志（Log）
- 查看信息（Info）

### 6.3 分支策略

支持一键执行标准分支策略：
- **Git Flow：** 从 develop 创建 feature 分支，完成后合并回 develop
- **GitHub Flow：** 从 main 创建功能分支
- **Release Branch：** 从 main 创建发布分支

### 6.4 冲突检测

在合并分支前，可先执行冲突检测：
1. 输入源分支和目标分支
2. 系统尝试合并并检测冲突
3. 返回冲突文件列表
4. 自动回滚测试合并，不影响工作区

## 七、仪表板

**入口：** 工具栏点击 📊 "仪表板" 按钮

**显示内容：**
- **在线服务器数：** 当前在线/总数
- **总任务数：** 所有项目的任务总数
- **进行中：** 正在执行的任务数
- **已完成：** 已完成的任务数
- **整体进度：** 进度条 + 百分比
- **服务器任务分布：** 每台服务器分配的任务数
- **最近任务：** 最近 10 条任务及其状态

数据每 5 秒自动刷新，也可点击刷新按钮手动刷新。

## 八、健康检查

点击工具栏的 **🔄** 按钮，批量检查所有服务器的在线状态。
- 绿色圆点：在线
- 灰色圆点：离线

## 九、今日鸡蛋（Egg of Today）

**入口：** 工具栏点击 🥚 图标

功能：连接 OpenRouter API 获取免费模型列表，创建模型组合并检查可用性。

## 十、Hermes Studio 端要求

服务器需启用以下 API 端点：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/api/auth/login` | POST | 用户认证 |
| `/api/auth/status` | GET | 认证状态 |
| `/api/studio/sessions` | GET | 会话列表 |
| `/api/studio/sessions/{id}` | GET | 会话详情 |
| `/api/studio/sessions/{id}` | DELETE | 删除会话 |
| `/api/studio/sessions/{id}/rename` | POST | 重命名会话 |
| `/api/studio/chat-run/runs` | POST | 执行对话 |
| `/api/studio/files/list` | GET | 列出文件 |
| `/api/studio/files/read` | GET | 读取文件 |
| `/api/studio/files/write` | PUT | 写入文件 |

## 十一、Hermes Proxy 模式部署

### 启动 hermes-proxy

```bash
./hermes-proxy-linux -config config.json -admin :8081
```

### 配置文件示例

```json
{
  "listen": ":8080",
  "admin": {
    "enabled": true,
    "token": "your-admin-token"
  },
  "auth": {
    "method": "static_token",
    "token": "proxy-connection-token"
  },
  "servers": [
    {
      "id": "office",
      "name": "办公室服务器",
      "url": "http://192.168.1.100:3000",
      "enabled": true
    }
  ]
}
```

### 在 hermes-hive 中配置

1. Proxy URL: `https://your-proxy-host:8080`
2. Admin Token: 与配置文件 `admin.token` 一致
3. 开启 Use Encryption（WSS）

## 十二、常见问题

**Q: 双击服务器无反应？**
A: 单击即可选中，不需要双击。选中后右侧自动加载会话列表。

**Q: 连接失败怎么办？**
A: 检查：
- URL 是否正确（包含 http:// 或 https://）
- Hermes Studio 是否已启动
- 网络是否可达（防火墙/路由）
- 是否需要认证（开启 Authentication 填写账号密码）

**Q: Proxy 模式获取不到服务器列表？**
A: 检查：
- Proxy URL 和 Admin Token 是否正确
- hermes-proxy 是否正常运行
- 代理端是否已配置后端服务器

**Q: 如何切换模式？**
A: 点击右上角 ⚙️ 进入全局配置，切换后保存即可。

**Q: 流水线执行失败了怎么办？**
A: 查看"日志"标签页的错误信息，根据提示修复后点击"重置"再重新执行。支持断点续传——已完成的任务不会重复执行。

**Q: 如何分配任务到指定服务器？**
A: 在流水线编辑界面，点击任务右侧的服务器选择器，选择目标服务器。未指定时自动分配给在线服务器。

## 十三、项目结构

```
hermes-hive/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/                      # 数据模型
│   │   ├── models.dart              # 服务器/会话模型
│   │   ├── task_models.dart         # 任务/流水线模型
│   │   ├── egg_models.dart          # 鸡蛋功能模型
│   │   └── global_config.dart       # 全局配置模型
│   ├── providers/                   # 状态管理
│   │   ├── server_provider.dart     # 服务器管理
│   │   ├── chat_provider.dart       # 聊天管理
│   │   ├── pipeline_provider.dart   # 流水线管理
│   │   ├── version_control_provider.dart  # 版本控制
│   │   ├── egg_provider.dart        # 鸡蛋功能
│   │   ├── global_config_provider.dart
│   │   ├── locale_provider.dart
│   │   ├── prompt_provider.dart
│   │   └── debug_logger.dart
│   ├── services/                    # 业务服务
│   │   ├── hermes_api_client.dart   # Hermes API 客户端
│   │   ├── proxy_client.dart        # 代理客户端
│   │   ├── pipeline_engine.dart     # 流水线引擎
│   │   ├── file_sync_engine.dart    # 文件同步引擎
│   │   ├── session_manager.dart     # 会话/结果管理
│   │   ├── version_control.dart     # 版本控制桥接
│   │   ├── dashboard_service.dart   # 仪表板/调度
│   │   ├── pipeline_persistence.dart # 状态持久化
│   │   ├── openrouter_service.dart  # OpenRouter API
│   │   └── egg_storage.dart
│   ├── screens/                     # 界面
│   │   ├── home_screen.dart         # 主页
│   │   ├── chat_screen.dart         # 聊天界面
│   │   ├── pipeline_screen.dart     # 流水线界面
│   │   ├── version_control_screen.dart  # 版本控制界面
│   │   ├── dashboard_screen.dart    # 仪表板
│   │   ├── egg_page.dart            # 鸡蛋功能
│   │   ├── server_config_screen.dart
│   │   └── global_config_screen.dart
│   ├── widgets/                     # 公共组件
│   └── l10n/                        # 国际化
│       ├── app_en.arb
│       └── app_zh.arb
├── hermes-proxy/                    # Go 代理服务器
├── doc/                             # 设计文档
└── scripts/                         # 工具脚本
```

## 十四、技术栈

- **前端：** Flutter 3.44.0 / Dart 3.12.0
- **状态管理：** Provider
- **本地存储：** SharedPreferences
- **网络：** HTTP + WebSocket
- **代理：** Go (X25519 + ChaCha20-Poly1305)
- **目标平台：** Linux (x64)
