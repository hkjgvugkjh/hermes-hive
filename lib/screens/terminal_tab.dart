import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';
import '../services/hermes_api_client.dart';
import '../providers/debug_logger.dart';

final _dangerousPatterns = [
  RegExp(r'rm\s+-[rfRF]+\s'),
  RegExp(r'sudo\s+'),
  RegExp(r'format\s+'),
  RegExp(r'dd\s+if='),
  RegExp(r'mkfs\.'),
  RegExp(r'chmod\s+-R\s+777'),
  RegExp(r'chown\s+-R'),
  RegExp(r'find\s+.*-exec\s+rm'),
  RegExp(r'git\s+push\s+--force'),
  RegExp(r'git\s+reset\s+--hard'),
  RegExp(r'git\s+clean\s+-fd'),
  RegExp(r'docker\s+rm\s+-f'),
  RegExp(r'npm\s+uninstall\s+-g'),
  RegExp(r'pip\s+uninstall\s+-y'),
  RegExp(r'shutdown\s+'),
  RegExp(r'reboot\s+'),
  RegExp(r'kill\s+-9'),
  RegExp(r'pkill\s+-9'),
];

bool isDangerousCommand(String command) {
  return _dangerousPatterns.any((p) => p.hasMatch(command));
}

class TerminalTab extends StatefulWidget {
  final ServerConfig server;

  const TerminalTab({super.key, required this.server});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final List<String> _history = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _sessionId;
  List<QuickCommand> _quickCommands = [];

  @override
  void initState() {
    super.initState();
    _loadQuickCommands();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _connectWebSocket() async {
    try {
      final client = HermesApiClient(widget.server);
      final loggedIn = await client.ensureLoggedIn();
      
      if (!loggedIn) {
        _addOutput('错误: 登录失败，请检查用户名和密码');
        return;
      }
      
      final token = client.token;
      final wsScheme = widget.server.baseUrl.startsWith('https') ? 'wss' : 'ws';
      final host = widget.server.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      
      final uri = token != null && token.isNotEmpty
          ? Uri.parse('$wsScheme://$host/api/hermes/terminal?token=$token')
          : Uri.parse('$wsScheme://$host/api/hermes/terminal');
      
      DebugLogger.instance.info('Terminal: connecting to $uri');
      
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      
      setState(() => _isConnected = true);
      _addOutput('已连接到 ${widget.server.name}');
      
      _channel!.stream.listen(
        (data) {
          _handleMessage(data.toString());
        },
        onDone: () {
          setState(() => _isConnected = false);
          _addOutput('连接已断开');
        },
        onError: (e) {
          setState(() => _isConnected = false);
          _addOutput('连接错误: $e');
          DebugLogger.instance.error('Terminal WebSocket error', e.toString());
        },
      );
    } catch (e) {
      _addOutput('连接失败: $e');
      DebugLogger.instance.error('Terminal connection failed', e.toString());
    }
  }

  void _handleMessage(String data) {
    DebugLogger.instance.info('Terminal received: ${data.length} chars');
    try {
      final msg = jsonDecode(data);
      final type = msg['type'];
      
      switch (type) {
        case 'created':
          _sessionId = msg['id'] ?? msg['sessionId'];
          _addOutput('终端已创建 (PID: ${msg['pid']}, Shell: ${msg['shell']})');
          break;
        case 'switched':
          _addOutput('已切换到会话: ${msg['id']}');
          break;
        case 'exited':
          _addOutput('会话已退出 (退出码: ${msg['exitCode']})');
          break;
        case 'error':
          _addOutput('错误: ${msg['message']}');
          break;
        default:
          _addOutput(data);
      }
    } catch (e) {
      // Raw terminal output (not JSON)
      _addOutput(data);
    }
  }

  void _sendCommand(String command) {
    if (command.trim().isEmpty) return;
    if (!_isConnected) {
      _addOutput('未连接到服务器');
      return;
    }
    if (_sessionId == null) {
      _addOutput('等待终端连接...');
      return;
    }
    if (isDangerousCommand(command)) {
      _showDangerousCommandDialog(command);
      return;
    }
    _addOutput('\$ $command');
    // Hermes terminal protocol: send raw text directly to PTY
    _channel?.sink.add('$command\n');
    _controller.clear();
    _scrollToBottom();
  }

  void _showDangerousCommandDialog(String command) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('高风险操作'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('即将执行以下命令：'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.grey[200],
              child: Text(command, style: TextStyle(fontFamily: 'monospace')),
            ),
            SizedBox(height: 8),
            Text('此操作可能不可逆，是否继续？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addOutput('\$ $command (已取消)');
            },
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _channel?.sink.add('$command\n');
              _controller.clear();
              _scrollToBottom();
            },
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
  }

  void _addOutput(String text) {
    setState(() {
      _history.add(text);
      if (_history.length > 1000) {
        _history.removeRange(0, _history.length - 1000);
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadQuickCommands() async {
    final commands = await QuickCommandStorage.load();
    setState(() => _quickCommands = commands);
  }

  Future<void> _saveQuickCommands() async {
    await QuickCommandStorage.save(_quickCommands);
  }

  Future<void> _addQuickCommand() async {
    final nameController = TextEditingController();
    final cmdController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加快捷命令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cmdController,
              decoration: const InputDecoration(labelText: '命令'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '描述（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('添加')),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty && cmdController.text.isNotEmpty) {
      setState(() {
        _quickCommands.add(QuickCommand(
          name: nameController.text,
          command: cmdController.text,
          description: descController.text.isEmpty ? null : descController.text,
        ));
      });
      await _saveQuickCommands();
    }
  }

  Future<void> _deleteQuickCommand(int index) async {
    setState(() => _quickCommands.removeAt(index));
    await _saveQuickCommands();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Text('快捷命令', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _addQuickCommand,
                      tooltip: '添加',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _quickCommands.isEmpty
                    ? Center(child: Text('暂无快捷命令', style: TextStyle(color: Colors.grey[500], fontSize: 12)))
                    : ListView.builder(
                        itemCount: _quickCommands.length,
                        itemBuilder: (context, index) {
                          final cmd = _quickCommands[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: ListTile(
                              dense: true,
                              title: Text(cmd.name, style: const TextStyle(fontSize: 13)),
                              subtitle: cmd.description != null ? Text(cmd.description!, style: const TextStyle(fontSize: 11)) : null,
                              onTap: () => _sendCommand(cmd.command),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 16),
                                onPressed: () => _deleteQuickCommand(index),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
                child: Row(
                  children: [
                    Icon(_isConnected ? Icons.circle : Icons.circle_outlined, size: 12, color: _isConnected ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Text(_isConnected ? '已连接 ($_sessionId)' : '未连接', style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    if (!_isConnected)
                      TextButton.icon(
                        onPressed: _connectWebSocket,
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('连接'),
                      )
                    else ...[
                      TextButton.icon(
                        onPressed: () {
                          if (_sessionId != null) {
                            _channel?.sink.add(jsonEncode({
                              'type': 'close',
                              'sessionId': _sessionId,
                            }));
                          }
                        },
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('关闭'),
                      ),
                      TextButton.icon(
                        onPressed: () => _channel?.sink.close(),
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('断开'),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.black87,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      return SelectableText.rich(
                        _parseAnsiToTextSpan(_history[index]),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      );
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _history.isEmpty ? null : () async {
                        final text = _history.join('\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制全部'),
                    ),
                    TextButton.icon(
                      onPressed: _history.isEmpty ? null : () {
                        setState(() => _history.clear());
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black87,
                child: Row(
                  children: [
                    const Text('\$ ', style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _sendCommand,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, size: 18, color: Colors.greenAccent),
                      onPressed: () => _sendCommand(_controller.text),
                      tooltip: '发送',
                    ),
                  ],
                ),
              ),
            ]
          ),
        ),
      ],
    );
  }

  TextSpan _parseAnsiToTextSpan(String text) {
    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    
    Color currentColor = Colors.greenAccent;
    Color? currentBgColor;
    bool isBold = false;
    
    int i = 0;
    while (i < text.length) {
      // Check for ESC character (0x1B)
      if (text.codeUnitAt(i) == 0x1B) {
        // Flush buffer
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(
            text: buffer.toString(),
            style: TextStyle(
              color: currentColor,
              backgroundColor: currentBgColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ));
          buffer.clear();
        }
        
        if (i + 1 >= text.length) {
          i++;
          continue;
        }
        
        final nextChar = text[i + 1];
        
        // Handle CSI sequences: ESC[...
        if (nextChar == '[') {
          int j = i + 2;
          final params = <int>[];
          String paramBuffer = '';
          
          while (j < text.length) {
            final c = text[j];
            final cCode = c.codeUnitAt(0);
            
            // Parameter bytes: 0x30-0x3F (0-9, :, ;, <, =, >, ?)
            if (cCode >= 0x30 && cCode <= 0x3F) {
              paramBuffer += c;
              j++;
            }
            // Intermediate bytes: 0x20-0x2F
            else if (cCode >= 0x20 && cCode <= 0x2F) {
              j++;
            }
            // Final byte: 0x40-0x7E
            else {
              if (paramBuffer.isNotEmpty) {
                params.add(int.tryParse(paramBuffer) ?? 0);
                paramBuffer = '';
              }
              
              // Process SGR (color) codes: ESC[...m
              if (c == 'm') {
                for (final code in params) {
                  switch (code) {
                    case 0: // Reset
                      currentColor = Colors.greenAccent;
                      currentBgColor = null;
                      isBold = false;
                      break;
                    case 1: // Bold/Bright
                      isBold = true;
                      break;
                    case 22: // Normal intensity
                      isBold = false;
                      break;
                    // Standard foreground colors
                    case 30: currentColor = Colors.black; break;
                    case 31: currentColor = const Color(0xFFCC0000); break;
                    case 32: currentColor = const Color(0xFF00CC00); break;
                    case 33: currentColor = const Color(0xFFCCCC00); break;
                    case 34: currentColor = const Color(0xFF0000CC); break;
                    case 35: currentColor = const Color(0xFFCC00CC); break;
                    case 36: currentColor = const Color(0xFF00CCCC); break;
                    case 37: currentColor = const Color(0xFFCCCCCC); break;
                    case 39: currentColor = Colors.greenAccent; break;
                    // Bright foreground colors
                    case 90: currentColor = const Color(0xFF666666); break;
                    case 91: currentColor = const Color(0xFFFF0000); break;
                    case 92: currentColor = const Color(0xFF00FF00); break;
                    case 93: currentColor = const Color(0xFFFFFF00); break;
                    case 94: currentColor = const Color(0xFF0000FF); break;
                    case 95: currentColor = const Color(0xFFFF00FF); break;
                    case 96: currentColor = const Color(0xFF00FFFF); break;
                    case 97: currentColor = Colors.white; break;
                    // Standard background colors
                    case 40: currentBgColor = Colors.black; break;
                    case 41: currentBgColor = const Color(0xFFCC0000); break;
                    case 42: currentBgColor = const Color(0xFF00CC00); break;
                    case 43: currentBgColor = const Color(0xFFCCCC00); break;
                    case 44: currentBgColor = const Color(0xFF0000CC); break;
                    case 45: currentBgColor = const Color(0xFFCC00CC); break;
                    case 46: currentBgColor = const Color(0xFF00CCCC); break;
                    case 47: currentBgColor = const Color(0xFFCCCCCC); break;
                    case 49: currentBgColor = null; break;
                    // Bright background colors
                    case 100: currentBgColor = const Color(0xFF666666); break;
                    case 101: currentBgColor = const Color(0xFFFF0000); break;
                    case 102: currentBgColor = const Color(0xFF00FF00); break;
                    case 103: currentBgColor = const Color(0xFFFFFF00); break;
                    case 104: currentBgColor = const Color(0xFF0000FF); break;
                    case 105: currentBgColor = const Color(0xFFFF00FF); break;
                    case 106: currentBgColor = const Color(0xFF00FFFF); break;
                    case 107: currentBgColor = Colors.white; break;
                  }
                }
              }
              // Skip other CSI sequences (cursor movement, etc.)
              j++;
              break;
            }
          }
          i = j;
        }
        // Handle OSC sequences: ESC]...BEL
        else if (nextChar == ']') {
          int j = i + 2;
          while (j < text.length && text[j] != '\x07') {
            j++;
          }
          i = j + 1; // Skip past BEL
        }
        // Handle simple ESC sequences
        else {
          i += 2;
        }
      } else {
        buffer.write(text[i]);
        i++;
      }
    }
    
    // Flush remaining buffer
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(
        text: buffer.toString(),
        style: TextStyle(
          color: currentColor,
          backgroundColor: currentBgColor,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }
    
    if (spans.isEmpty) {
      return TextSpan(text: text, style: const TextStyle(color: Colors.greenAccent));
    }
    
    return TextSpan(children: spans);
  }
}

class QuickCommand {
  final String id;
  String name;
  String command;
  String? description;
  DateTime createdAt;

  QuickCommand({
    String? id,
    required this.name,
    required this.command,
    this.description,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
      };

  factory QuickCommand.fromJson(Map<String, dynamic> json) => QuickCommand(
        id: json['id'],
        name: json['name'],
        command: json['command'],
        description: json['description'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class QuickCommandStorage {
  static const String _key = 'hermes_hive_quick_commands';

  static Future<List<QuickCommand>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final List<dynamic> json = jsonDecode(data);
    return json.map((j) => QuickCommand.fromJson(j)).toList();
  }

  static Future<void> save(List<QuickCommand> commands) async {
    final prefs = await SharedPreferences.getInstance();
    final json = commands.map((c) => c.toJson()).toList();
    await prefs.setString(_key, jsonEncode(json));
  }
}
