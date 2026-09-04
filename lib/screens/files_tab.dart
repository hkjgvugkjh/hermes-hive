import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/hermes_api_client.dart';

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
  final Map<String, bool> _expandedDirs = {};
  final Map<String, List<FileNode>> _dirCache = {};

  @override
  void initState() {
    super.initState();
    _loadFiles(_currentPath);
  }

  Future<void> _loadFiles(String path) async {
    setState(() => _isLoading = true);
    try {
      final client = HermesApiClient(widget.server);
      await client.ensureLoggedIn();
      final files = await client.listFiles(path);
      setState(() {
        _currentFiles = files;
        _currentPath = path;
        _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Directory tree
        SizedBox(
          width: 250,
          child: Column(
            children: [
              // Toolbar
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
              // Breadcrumb
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
              // File list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : ListView.builder(
                        itemCount: _currentFiles.length,
                        itemBuilder: (context, index) {
                          final file = _currentFiles[index];
                          return _buildFileTile(file);
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // File editor
        Expanded(
          child: _selectedFile == null
              ? const Center(child: Text('选择文件以编辑'))
              : Column(
                  children: [
                    // Editor toolbar
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
                    // Editor
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

  Widget _buildFileTile(FileNode file) {
    final isDirectory = file.isDirectory;
    return ListTile(
      dense: true,
      leading: Icon(
        isDirectory ? Icons.folder : Icons.insert_drive_file,
        size: 18,
        color: isDirectory ? Colors.amber : Colors.grey,
      ),
      title: Text(file.name, style: const TextStyle(fontSize: 13)),
      onTap: () {
        if (isDirectory) {
          _loadFiles(file.path);
        } else {
          _loadFileContent(file.path);
        }
      },
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        onSelected: (value) {
          if (value == 'delete') {
            _deleteFile(file.path);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'delete', child: Text('删除', style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}


