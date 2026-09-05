import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/hermes_api_client.dart';
import '../providers/chat_provider.dart';
import '../providers/debug_logger.dart';

class FilesTab extends StatefulWidget {
  final ServerConfig server;

  const FilesTab({super.key, required this.server});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  String _currentPath = '/';
  List<FileNode> _currentFiles = [];
  bool _isLoading = true;
  String? _selectedFile;
  String _fileContent = '';
  bool _isDirty = false;
  final TextEditingController _editorController = TextEditingController();
  final Set<String> _expandedDirs = {};
  final Map<String, List<FileNode>> _dirCache = {};

  @override
  void initState() {
    super.initState();
    _loadFiles(_currentPath, isRoot: true);
  }

  Future<void> _loadFiles(String path, {bool isRoot = false}) async {
    setState(() => _isLoading = true);
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      final files = await client.listFiles(path);
      setState(() {
        _currentFiles = files;
        _currentPath = path;
        _isLoading = false;
        if (isRoot) {
          _dirCache.clear();
        }
        _dirCache[path] = files;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _loadFileContent(String path) async {
    setState(() => _isLoading = true);
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      final content = await client.readFile(path);
      setState(() {
        _selectedFile = path;
        _fileContent = content;
        _editorController.text = content;
        _isDirty = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('读取文件失败: $e')));
      }
    }
  }

  Future<void> _saveFile() async {
    if (_selectedFile == null) return;
    
    // Confirm before overwriting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认保存'),
        content: Text('确定要保存对 ${_selectedFile!.split('/').last} 的修改吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (confirm != true) return;
    
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      await client.writeFile(_selectedFile!, _editorController.text);
      setState(() {
        _fileContent = _editorController.text;
        _isDirty = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  Future<void> _createFile() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '文件名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('创建')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final path = _currentPath == '/' ? '/$result' : '$_currentPath/$result';
      try {
        final client = HermesApiClient(widget.server);
        await client.ensureLoggedIn();
        await client.writeFile(path, '');
        _loadFiles(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
        }
      }
    }
  }

  Future<void> _createDirectory() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建目录'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '目录名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('创建')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final path = _currentPath == '/' ? '/$result' : '$_currentPath/$result';
      try {
        final client = HermesApiClient(widget.server);
        await client.ensureLoggedIn();
        await client.createDirectory(path);
        _loadFiles(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
        }
      }
    }
  }

  Future<void> _deleteFile(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 $path 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final client = HermesApiClient(widget.server);
        await client.ensureLoggedIn();
        await client.deleteFile(path);
        if (_selectedFile == path) {
          setState(() {
            _selectedFile = null;
            _fileContent = '';
            _editorController.clear();
          });
        }
        _loadFiles(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Future<void> _startSessionInDirectory(String dirPath) async {
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      
      // Create a new session with the directory as working directory
      final response = await client.runChat(
        input: '工作目录: $dirPath',
      );
      
      if (response.success && response.sessionId != null) {
        // Switch to sessions tab and select the new session
        if (mounted) {
          // Find the parent HomeScreen and switch to sessions tab
          final homeState = context.findAncestorStateOfType<State>();
          if (homeState != null && homeState.mounted) {
            // Use a callback or provider to switch tabs
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已创建会话: ${response.sessionId!.substring(0, 8)}')),
            );
          }
          // Refresh sessions list
          final chatProvider = context.read<ChatProvider>();
          chatProvider.refreshSessions();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建会话失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 250,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Text('文件', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: () => _loadFiles(_currentPath),
                      tooltip: '刷新',
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder, size: 18),
                      onPressed: _createDirectory,
                      tooltip: '新建目录',
                    ),
                    IconButton(
                      icon: const Icon(Icons.note_add, size: 18),
                      onPressed: _createFile,
                      tooltip: '新建文件',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      onPressed: _currentPath != '/' ? () {
                        final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
                        _loadFiles(parent.isEmpty ? '/' : parent);
                      } : null,
                      tooltip: '上级目录',
                    ),
                    Expanded(
                      child: Text(
                        _currentPath,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _buildFileList(),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedFile == null
              ? const Center(child: Text('选择文件以编辑'))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
                      child: Row(
                        children: [
                          Text(_selectedFile!, style: const TextStyle(fontSize: 12)),
                          if (_isDirty) const Text(' *', style: TextStyle(color: Colors.red)),
                          const Spacer(),
                          if (_isDirty)
                            TextButton.icon(
                              onPressed: _saveFile,
                              icon: const Icon(Icons.save, size: 16),
                              label: const Text('保存'),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _editorController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        onChanged: (_) => setState(() => _isDirty = true),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFileList() {
    if (_currentFiles.isEmpty) {
      return const Center(child: Text('目录为空', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _currentFiles.length,
      itemBuilder: (context, index) {
        final file = _currentFiles[index];
        return _buildFileTile(file, 0);
      },
    );
  }

  Widget _buildFileTile(FileNode file, int depth) {
    final isDirectory = file.isDirectory;
    final isExpanded = _expandedDirs.contains(file.path);
    
    return Column(
      children: [
        InkWell(
          onTap: () {
            if (isDirectory) {
              setState(() {
                if (isExpanded) {
                  _expandedDirs.remove(file.path);
                } else {
                  _expandedDirs.add(file.path);
                  if (!_dirCache.containsKey(file.path)) {
                    _loadSubDirectory(file.path);
                  }
                }
              });
            } else {
              _loadFileContent(file.path);
            }
          },
          onSecondaryTapDown: isDirectory ? (details) {
            _showDirectoryContextMenu(details.globalPosition, file.path);
          } : null,
          child: Container(
            padding: EdgeInsets.only(left: 8.0 + depth * 16.0, right: 8.0, top: 8.0, bottom: 8.0),
            child: Row(
              children: [
                Icon(
                  isDirectory ? (isExpanded ? Icons.folder_open : Icons.folder) : Icons.insert_drive_file,
                  size: 18,
                  color: isDirectory ? Colors.amber : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDirectory)
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: Colors.grey,
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteFile(file.path);
                    } else if (value == 'new_session') {
                      _startSessionInDirectory(file.path);
                    }
                  },
                  itemBuilder: (context) => [
                    if (isDirectory)
                      const PopupMenuItem(value: 'new_session', child: Text('在此目录发起会话')),
                    const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isDirectory && isExpanded && _dirCache.containsKey(file.path))
          ...(_dirCache[file.path]?.map((subFile) => _buildFileTile(subFile, depth + 1)) ?? []),
      ],
    );
  }

  Future<void> _loadSubDirectory(String path) async {
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      final files = await client.listFiles(path);
      setState(() {
        _dirCache[path] = files;
      });
    } catch (e) {
      DebugLogger.instance.error('Failed to load subdirectory $path: $e');
    }
  }

  void _showDirectoryContextMenu(Offset position, String dirPath) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'new_session',
          child: Row(
            children: [
              const Icon(Icons.chat, size: 18),
              const SizedBox(width: 8),
              Text('在 ${dirPath.split('/').last} 发起会话'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_file',
          child: Row(
            children: [
              Icon(Icons.note_add, size: 18),
              SizedBox(width: 8),
              Text('新建文件'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder, size: 18),
              SizedBox(width: 8),
              Text('新建目录'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'new_session') {
        _startSessionInDirectory(dirPath);
      } else if (value == 'new_file') {
        _createFile();
      } else if (value == 'new_folder') {
        _createDirectory();
      } else if (value == 'delete') {
        _deleteFile(dirPath);
      }
    });
  }
}
