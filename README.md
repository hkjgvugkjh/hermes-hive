# Hermes Hive 使用说明

## 一、产品简介

Hermes Hive 是 Hermes Studio 的多服务器管理工具，支持在一个界面中管理多个 Hermes Web UI 服务器。

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

## 五、健康检查

点击工具栏的 **🔄** 按钮，批量检查所有服务器的在线状态。
- 绿色圆点：在线
- 灰色圆点：离线

## 六、Hermes Studio 端要求

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

## 七、Hermes Proxy 模式部署

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

## 八、常见问题

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
