// Package admin contains the embedded web UI HTML/JS.
package admin

const webUIHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Hermes Proxy Admin</title>
<script src="/qrcode.min.js"></script>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; }
.container { max-width: 1200px; margin: 0 auto; padding: 20px; }
.header { background: #1a1a2e; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
.header h1 { font-size: 24px; margin-bottom: 8px; }
.header p { opacity: 0.8; font-size: 14px; }
.card { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
.card h2 { font-size: 18px; margin-bottom: 16px; color: #1a1a2e; }
.form-group { margin-bottom: 12px; }
.form-group label { display: block; font-size: 13px; font-weight: 500; margin-bottom: 4px; color: #555; }
.form-group input, .form-group select { width: 100%; padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
.form-group input:focus, .form-group select:focus { outline: none; border-color: #4a90d9; }
.btn { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; transition: all 0.2s; }
.btn-primary { background: #4a90d9; color: white; }
.btn-primary:hover { background: #357abd; }
.btn-danger { background: #e74c3c; color: white; }
.btn-danger:hover { background: #c0392b; }
.btn-success { background: #27ae60; color: white; }
.btn-success:hover { background: #219a52; }
.btn-secondary { background: #95a5a6; color: white; }
.btn-secondary:hover { background: #7f8c8d; }
.btn-sm { padding: 4px 10px; font-size: 12px; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.server-list { list-style: none; }
.server-item { display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 6px; margin-bottom: 8px; }
.server-item:hover { background: #f9f9f9; }
.server-info { flex: 1; }
.server-name { font-weight: 500; font-size: 15px; }
.server-url { font-size: 13px; color: #888; margin-top: 2px; }
.server-actions { display: flex; gap: 8px; }
.status-badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 500; }
.status-online { background: #d4edda; color: #155724; }
.status-offline { background: #f8d7da; color: #721c24; }
.status-unknown { background: #e2e3e5; color: #383d41; }
.auth-section { display: flex; gap: 20px; }
.auth-section .form-group { flex: 1; }
.test-result { margin-top: 8px; padding: 8px 12px; border-radius: 4px; font-size: 13px; }
.test-success { background: #d4edda; color: #155724; }
.test-fail { background: #f8d7da; color: #721c24; }
.token-input { position: fixed; top: 20px; right: 20px; background: white; padding: 12px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.15); display: none; z-index: 100; }
.token-input.show { display: block; }
.token-input input { width: 200px; padding: 6px 10px; border: 1px solid #ddd; border-radius: 4px; }
.toast { position: fixed; bottom: 20px; right: 20px; padding: 12px 20px; border-radius: 6px; color: white; font-size: 14px; z-index: 200; animation: slideIn 0.3s ease; }
.toast-success { background: #27ae60; }
.toast-error { background: #e74c3c; }
@keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
.qr-container { display: flex; flex-direction: column; align-items: center; padding: 20px; margin-top: 16px; border-top: 1px solid #eee; }
.qr-container canvas { border: 1px solid #ddd; border-radius: 8px; padding: 12px; }
.qr-content { font-family: monospace; font-size: 12px; color: #666; margin-top: 12px; word-break: break-all; max-width: 400px; text-align: center; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>Hermes Proxy Admin</h1>
    <p>管理 Hermes Studio 服务器清单和连接配置</p>
  </div>

  <!-- Proxy Settings Card -->
  <div class="card">
    <h2>代理对外配置</h2>
    <div class="auth-section">
      <div class="form-group">
        <label>WebSocket 监听端口 *</label>
        <input type="text" id="proxyListen" placeholder=":8649">
      </div>
      <div class="form-group">
        <label>WebSocket 路径</label>
        <input type="text" id="proxyWSPath" value="/ws" placeholder="/ws">
      </div>
      <div class="form-group">
        <label>Admin 端口 *</label>
        <input type="text" id="proxyAdminPort" placeholder=":8650">
      </div>
    </div>
    <div class="auth-section">
      <div class="form-group">
        <label>连接 Token</label>
        <input type="text" id="proxyToken" placeholder="客户端连接时使用的令牌">
      </div>
      <div class="form-group">
        <label>Admin Token</label>
        <input type="text" id="proxyAdminToken" placeholder="管理 API 访问令牌">
      </div>
      <div class="form-group">
        <label>外部访问主机</label>
        <input type="text" id="proxyHost" placeholder="10.10.164.90">
      </div>
    </div>
    <div style="display: flex; gap: 10px; margin-top: 12px;">
      <button class="btn btn-primary" id="btnValidate" onclick="validateConfig()">验证配置</button>
      <button class="btn btn-success" id="btnSaveProxy" onclick="saveProxyConfig()" disabled>保存配置</button>
    </div>
    <div id="validateResult"></div>
    <div id="qrSection" class="qr-container" style="display:none;">
      <div id="qrcode"></div>
      <div class="qr-content" id="qrContent"></div>
      <button class="btn btn-secondary btn-sm" onclick="copyQRContent()" style="margin-top:8px;">复制内容</button>
      <p style="font-size:12px;color:#888;margin-top:8px;">扫码配置 hermes-hive / hermes-reader</p>
    </div>
  </div>

  <div class="card">
    <h2>添加服务器</h2>
    <div class="auth-section">
      <div class="form-group">
        <label>服务器 ID *</label>
        <input type="text" id="serverId" placeholder="如: local, office, cloud">
      </div>
      <div class="form-group">
        <label>显示名称 *</label>
        <input type="text" id="serverName" placeholder="如: 本地服务器">
      </div>
    </div>
    <div class="form-group">
      <label>服务器 URL *</label>
      <input type="text" id="serverUrl" placeholder="http://192.168.1.100:3000">
    </div>
    <div class="auth-section">
      <div class="form-group">
        <label>用户名 (可选)</label>
        <input type="text" id="serverUsername" placeholder="用于自动登录">
      </div>
      <div class="form-group">
        <label>密码 (可选)</label>
        <input type="password" id="serverPassword" placeholder="用于自动登录">
      </div>
    </div>
    <div class="auth-section">
      <div class="form-group">
        <label>Profile</label>
        <input type="text" id="serverProfile" value="default" placeholder="default">
      </div>
      <div class="form-group">
        <label>状态</label>
        <select id="serverEnabled">
          <option value="true">启用</option>
          <option value="false">禁用</option>
        </select>
      </div>
    </div>
    <div style="display: flex; gap: 10px; margin-top: 12px;">
      <button class="btn btn-primary" onclick="addServer()">添加服务器</button>
      <button class="btn btn-success" onclick="testConnection()">测试连接</button>
    </div>
    <div id="testResult"></div>
  </div>

  <div class="card">
    <h2>服务器清单</h2>
    <ul class="server-list" id="serverList"></ul>
  </div>
</div>

<div class="token-input" id="tokenInput">
  <div class="form-group">
    <label>Admin Token</label>
    <input type="password" id="adminToken" placeholder="输入管理令牌">
  </div>
  <button class="btn btn-primary btn-sm" onclick="setToken()">确定</button>
</div>

<script>
let servers = [];
let adminToken = localStorage.getItem('adminToken') || '';
let qrCodeObj = null;

async function api(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (adminToken) headers['Authorization'] = 'Bearer ' + adminToken;
  const res = await fetch(path, { ...opts, headers });
  if (res.status === 401) {
    document.getElementById('tokenInput').classList.add('show');
    throw new Error('需要管理令牌');
  }
  return res.json();
}

function setToken() {
  adminToken = document.getElementById('adminToken').value;
  localStorage.setItem('adminToken', adminToken);
  document.getElementById('tokenInput').classList.remove('show');
  loadServers();
}

async function loadServers() {
  try {
    const data = await api('/api/servers');
    servers = data.servers || [];
    renderServers();
    loadProxySettings();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function loadProxySettings() {
  try {
    const data = await api('/api/config');
    if (data.listen) document.getElementById('proxyListen').value = data.listen;
    if (data.ws_path) document.getElementById('proxyWSPath').value = data.ws_path;
    if (data.admin_path) document.getElementById('proxyAdminPort').value = data.admin_path;
    if (data.host) document.getElementById('proxyHost').value = data.host;
    if (data.token) document.getElementById('proxyToken').value = data.token;
    if (data.admin_token) document.getElementById('proxyAdminToken').value = data.admin_token;
  } catch (e) {}
}

function renderServers() {
  const list = document.getElementById('serverList');
  if (servers.length === 0) {
    list.innerHTML = '<li style="text-align:center;color:#888;padding:20px;">暂无服务器配置</li>';
    return;
  }
  list.innerHTML = servers.map(s => '<li class="server-item">' +
    '<div class="server-info">' +
      '<div class="server-name">' + escapeHtml(s.name) + ' <span class="status-badge ' + (s.enabled ? 'status-online' : 'status-offline') + '">' + (s.enabled ? '启用' : '禁用') + '</span></div>' +
      '<div class="server-url">' + escapeHtml(s.url) + (s.username ? ' · ' + escapeHtml(s.username) : '') + '</div>' +
    '</div>' +
    '<div class="server-actions">' +
      '<button class="btn btn-primary btn-sm" onclick="editServer(\'' + s.id + '\')">编辑</button>' +
      '<button class="btn btn-danger btn-sm" onclick="deleteServer(\'' + s.id + '\')">删除</button>' +
    '</div>' +
  '</li>').join('');
}

async function validateConfig() {
  const btn = document.getElementById('btnValidate');
  btn.disabled = true;
  btn.textContent = '验证中...';
  
  const resultDiv = document.getElementById('validateResult');
  const qrSection = document.getElementById('qrSection');
  qrSection.style.display = 'none';
  
  const req = {
    listen: document.getElementById('proxyListen').value.trim(),
    ws_path: document.getElementById('proxyWSPath').value.trim() || '/ws',
    admin_port: document.getElementById('proxyAdminPort').value.trim(),
    token: document.getElementById('proxyToken').value.trim(),
    admin_token: document.getElementById('proxyAdminToken').value.trim(),
    host: document.getElementById('proxyHost').value.trim()
  };
  
  // If host is provided, test connectivity and token validity from browser
  if (req.host) {
    resultDiv.innerHTML = '<div class="test-result">正在测试连接...</div>';
    
    // Parse host to extract scheme, hostname, and port
    let host = req.host;
    let scheme = 'https';
    let hostname = host;
    
    if (hostname.startsWith('https://')) {
      scheme = 'https';
      hostname = hostname.substring(8);
    } else if (hostname.startsWith('http://')) {
      scheme = 'http';
      hostname = hostname.substring(7);
    }
    
    // Extract port from host
    let port = '';
    const portIdx = hostname.indexOf(':');
    if (portIdx !== -1) {
      port = hostname.substring(portIdx + 1);
      hostname = hostname.substring(0, portIdx);
    }
    
    // Use admin_port if no port in host
    const adminPort = port || req.admin_port.replace(/^:/, '') || '8650';
    
    // Build admin URL for testing
    const adminURL = scheme + '://' + hostname + ':' + adminPort + '/api/config';
    
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000);
      
      const resp = await fetch(adminURL, {
        method: 'GET',
        headers: {
          'Authorization': 'Bearer ' + req.admin_token
        },
        signal: controller.signal,
        mode: 'cors'
      });
      
      clearTimeout(timeoutId);
      
      if (resp.status === 401) {
        resultDiv.innerHTML = '<div class="test-result test-fail">✗ Token 无效（401 Unauthorized）</div>';
        document.getElementById('btnSaveProxy').disabled = true;
        btn.disabled = false;
        btn.textContent = '验证配置';
        return;
      } else if (resp.status !== 200) {
        resultDiv.innerHTML = '<div class="test-result test-fail">✗ 连接异常: HTTP ' + resp.status + '</div>';
        document.getElementById('btnSaveProxy').disabled = true;
        btn.disabled = false;
        btn.textContent = '验证配置';
        return;
      }
    } catch (e) {
      resultDiv.innerHTML = '<div class="test-result test-fail">✗ 连接失败: ' + e.message + '</div>';
      document.getElementById('btnSaveProxy').disabled = true;
      btn.disabled = false;
      btn.textContent = '验证配置';
      return;
    }
  }
  
  try {
    const data = await api('/api/validate-config', {
      method: 'POST',
      body: JSON.stringify(req)
    });
    
    if (data.valid) {
      resultDiv.innerHTML = '<div class="test-result test-success">✓ 配置有效</div>';
      document.getElementById('btnSaveProxy').disabled = false;
      
      // Show QR code
      qrSection.style.display = 'flex';
      
      // Parse host for QR code
      let host = req.host || window.location.hostname;
      let scheme = 'wss';
      let hostname = host;
      let port = '';
      
      // Extract scheme
      if (hostname.startsWith('https://')) {
        scheme = 'wss';
        hostname = hostname.substring(8);
      } else if (hostname.startsWith('http://')) {
        scheme = 'ws';
        hostname = hostname.substring(7);
      }
      
      // Extract port from host
      const portIdx = hostname.indexOf(':');
      if (portIdx !== -1) {
        port = hostname.substring(portIdx + 1);
        hostname = hostname.substring(0, portIdx);
      }
      
      // Use listen port if no port in host
      const wsPort = port || req.listen.replace(/^:/, '') || '8649';
      const adminPort = port || req.admin_port.replace(/^:/, '') || '8650';
      
      const wsUrl = scheme + '://' + hostname + ':' + wsPort + req.ws_path;
      const adminUrl = (scheme === 'wss' ? 'https://' : 'http://') + hostname + ':' + adminPort;
      const token = req.token || '';
      
      const qrContent = 'hermes-proxy://' + wsUrl + '?token=' + encodeURIComponent(token) + '&admin=' + encodeURIComponent(adminUrl);
      
      // Clear previous QR
      const qrDiv = document.getElementById('qrcode');
      qrDiv.innerHTML = '';
      if (qrCodeObj) qrCodeObj.clear();
      qrCodeObj = new QRCode(qrDiv, { text: qrContent, width: 200, height: 200 });
      
      document.getElementById('qrContent').textContent = qrContent;
    } else {
      resultDiv.innerHTML = '<div class="test-result test-fail">✗ ' + (data.errors || ['验证失败']).join('; ') + '</div>';
      document.getElementById('btnSaveProxy').disabled = true;
    }
  } catch (e) {
    resultDiv.innerHTML = '<div class="test-result test-fail">验证失败: ' + e.message + '</div>';
    document.getElementById('btnSaveProxy').disabled = true;
  } finally {
    btn.disabled = false;
    btn.textContent = '验证配置';
  }
}

async function saveProxyConfig() {
  const req = {
    listen: document.getElementById('proxyListen').value.trim(),
    ws_path: document.getElementById('proxyWSPath').value.trim(),
    admin_path: document.getElementById('proxyAdminPort').value.trim(),
    host: document.getElementById('proxyHost').value.trim(),
    auth: {
      method: 'static_token',
      static_token: { token: document.getElementById('proxyToken').value.trim() }
    },
    admin_token: document.getElementById('proxyAdminToken').value.trim()
  };
  
  try {
    await api('/api/config', { method: 'PUT', body: JSON.stringify(req) });
    showToast('配置已保存', 'success');
    document.getElementById('btnSaveProxy').disabled = true;
  } catch (e) {
    showToast('保存失败: ' + e.message, 'error');
  }
}

function copyQRContent() {
  const content = document.getElementById('qrContent').textContent;
  navigator.clipboard.writeText(content).then(() => showToast('已复制', 'success'));
}

async function addServer() {
  const server = {
    id: document.getElementById('serverId').value.trim(),
    name: document.getElementById('serverName').value.trim(),
    url: document.getElementById('serverUrl').value.trim(),
    username: document.getElementById('serverUsername').value.trim(),
    password: document.getElementById('serverPassword').value,
    profile: document.getElementById('serverProfile').value.trim() || 'default',
    enabled: document.getElementById('serverEnabled').value === 'true'
  };
  if (!server.id || !server.name || !server.url) {
    showToast('请填写必填字段', 'error');
    return;
  }
  try {
    await api('/api/servers', { method: 'POST', body: JSON.stringify(server) });
    showToast('服务器已添加', 'success');
    clearForm();
    loadServers();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function testConnection() {
  const url = document.getElementById('serverUrl').value.trim();
  const username = document.getElementById('serverUsername').value.trim();
  const password = document.getElementById('serverPassword').value;
  if (!url) { showToast('请输入服务器 URL', 'error'); return; }
  const resultDiv = document.getElementById('testResult');
  resultDiv.innerHTML = '<div class="test-result">测试中...</div>';
  try {
    const data = await api('/api/test', {
      method: 'POST',
      body: JSON.stringify({ url, username, password })
    });
    if (data.success) {
      resultDiv.innerHTML = '<div class="test-result test-success">连接成功!' + (data.login_ok ? ' (含登录验证)' : '') + '</div>';
    } else {
      resultDiv.innerHTML = '<div class="test-result test-fail">连接失败: ' + (data.error || '未知错误') + '</div>';
    }
  } catch (e) {
    resultDiv.innerHTML = '<div class="test-result test-fail">测试失败: ' + e.message + '</div>';
  }
}

function editServer(id) {
  const s = servers.find(x => x.id === id);
  if (!s) return;
  document.getElementById('serverId').value = s.id;
  document.getElementById('serverName').value = s.name;
  document.getElementById('serverUrl').value = s.url;
  document.getElementById('serverUsername').value = s.username || '';
  document.getElementById('serverPassword').value = s.password || '';
  document.getElementById('serverProfile').value = s.profile || 'default';
  document.getElementById('serverEnabled').value = String(s.enabled);
  window.scrollTo(0, 0);
}

async function deleteServer(id) {
  if (!confirm('确定要删除此服务器吗？')) return;
  try {
    await api('/api/servers/' + id, { method: 'DELETE' });
    showToast('服务器已删除', 'success');
    loadServers();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

function clearForm() {
  ['serverId','serverName','serverUrl','serverUsername','serverPassword'].forEach(id => {
    document.getElementById(id).value = '';
  });
  document.getElementById('serverProfile').value = 'default';
  document.getElementById('serverEnabled').value = 'true';
  document.getElementById('testResult').innerHTML = '';
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

function showToast(msg, type) {
  const toast = document.createElement('div');
  toast.className = 'toast toast-' + type;
  toast.textContent = msg;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3000);
}

loadServers();
</script>
</body>
</html>`
