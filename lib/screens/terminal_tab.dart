import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';
import '../services/hermes_api_client.dart';
import '../providers/debug_logger.dart';

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
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _sessionId;
  List<QuickCommand> _quickCommands = [];

  @override
  void initState() {
    super.initState();
    _loadQuickCommands();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connectWebSocket() async {
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      
      if (client.token == null || client.token!.isEmpty) {
        _addOutput('错误: 无法获取认证令牌，请先登录');
        return;
      }
      
      final token = client.token!;
      final wsScheme = widget.server.baseUrl.startsWith('https') ? 'wss' : 'ws';
      final host = widget.server.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      final uri = Uri.parse('$wsScheme://$host/api/hermes/terminal?token=$token');
      
      DebugLogger.instance.info('Terminal: connecting to $uri');
      
      _channel = WebSocketChannel.connect(uri);
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
    try {
      final msg = jsonDecode(data);
      final type = msg['type'];
      
      switch (type) {
        case 'created':
          _sessionId = msg['id'];
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
      _addOutput(data);
    }
  }

  void _sendCommand(String command) {
    if (command.trim().isEmpty) return;
    if (!_isConnected || _sessionId == null) {
      _addOutput('未连接到服务器');
      return;
    }
    _addOutput('\$ $command');
    _channel?.sink.add(jsonEncode({
      'type': 'input',
      'data': command,
    }));
    _controller.clear();
    _scrollToBottom();
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
            ],
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
                        _parseAnsiText(_history[index]),
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
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _sendCommand,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextSpan _parseAnsiText(String text) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\x1B\[([0-9;]*)([A-Za-z])');
    int lastEnd = 0;
    
    Color currentColor = Colors.greenAccent;
    Color? currentBgColor;
    bool isBold = false;
    
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
            color: currentColor,
            backgroundColor: currentBgColor,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ));
      }
      
      final params = match.group(1) ?? '';
      final command = match.group(2) ?? '';
      
      if (command == 'm') {
        final codes = params.isEmpty ? [0] : params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
        
        for (final code in codes) {
          switch (code) {
            case 0:
              currentColor = Colors.greenAccent;
              currentBgColor = null;
              isBold = false;
              break;
            case 1:
              isBold = true;
              break;
            case 30: currentColor = Colors.black; break;
            case 31: currentColor = Colors.red; break;
            case 32: currentColor = Colors.green; break;
            case 33: currentColor = Colors.yellow; break;
            case 34: currentColor = Colors.blue; break;
            case 35: currentColor = Colors.purple; break;
            case 36: currentColor = Colors.cyan; break;
            case 37: currentColor = Colors.white; break;
            case 90: currentColor = Colors.grey; break;
            case 91: currentColor = Colors.redAccent; break;
            case 92: currentColor = Colors.lightGreen; break;
            case 93: currentColor = const Color(0xFFFFFF00); break;
            case 94: currentColor = Colors.lightBlue; break;
            case 95: currentColor = Colors.pink; break;
            case 96: currentColor = Colors.lightBlue; break;
            case 97: currentColor = Colors.white; break;
            case 40: currentBgColor = Colors.black; break;
            case 41: currentBgColor = Colors.red; break;
            case 42: currentBgColor = Colors.green; break;
            case 43: currentBgColor = Colors.yellow; break;
            case 44: currentBgColor = Colors.blue; break;
            case 45: currentBgColor = Colors.purple; break;
            case 46: currentBgColor = Colors.cyan; break;
            case 47: currentBgColor = Colors.white; break;
          }
        }
      }
      
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
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
