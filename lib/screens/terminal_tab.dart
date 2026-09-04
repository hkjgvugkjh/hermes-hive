import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

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

  void _connectWebSocket() {
    try {
      final wsUrl = widget.server.baseUrl.replaceFirst('http', 'ws');
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/terminal'));
      setState(() => _isConnected = true);
      _addOutput('已连接到 ${widget.server.name}');
      
      _channel!.stream.listen(
        (data) => _addOutput(data.toString()),
        onDone: () {
          setState(() => _isConnected = false);
          _addOutput('连接已断开');
        },
        onError: (e) {
          setState(() => _isConnected = false);
          _addOutput('连接错误: $e');
        },
      );
    } catch (e) {
      _addOutput('连接失败: $e');
    }
  }

  void _sendCommand(String command) {
    if (command.trim().isEmpty) return;
    if (!_isConnected) {
      _addOutput('未连接到服务器');
      return;
    }
    _addOutput('\$ $command');
    _channel?.sink.add(command);
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
        // Quick commands panel
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
        // Terminal area
        Expanded(
          child: Column(
            children: [
              // Terminal toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
                child: Row(
                  children: [
                    Icon(_isConnected ? Icons.circle : Icons.circle_outlined, size: 12, color: _isConnected ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Text(_isConnected ? '已连接' : '未连接', style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    if (!_isConnected)
                      TextButton.icon(
                        onPressed: _connectWebSocket,
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('连接'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => _channel?.sink.close(),
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('断开'),
                      ),
                  ],
                ),
              ),
              // Terminal output
              Expanded(
                child: Container(
                  color: Colors.black87,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _history[index],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.greenAccent),
                      );
                    },
                  ),
                ),
              ),
              // Command input
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
