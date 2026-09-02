import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/models.dart';
import '../providers/server_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/debug_logger.dart';
import '../providers/prompt_provider.dart';
import '../widgets/debug_panel.dart';
import '../services/prompt_storage.dart';
import '../l10n/app_localizations.dart';

/// Chat screen for interacting with a Hermes server
class ChatScreen extends StatefulWidget {
  final ServerConfig server;

  const ChatScreen({super.key, required this.server});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _visibleMessageCount = 10;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    DebugLogger.instance.info('ChatScreen initState', 'server=${widget.server.name} url=${widget.server.url}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      final promptProvider = context.read<PromptProvider>();
      chatProvider.setPromptProvider(promptProvider);
      DebugLogger.instance.info('ChatScreen loading sessions...');
      chatProvider.loadSessions();
      chatProvider.loadModelGroups();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels < 50 && !_isLoadingMore) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    final provider = context.read<ChatProvider>();
    if (provider.currentMessages.length > _visibleMessageCount) {
      setState(() {
        _isLoadingMore = true;
        _visibleMessageCount = (_visibleMessageCount + 20).clamp(0, provider.currentMessages.length);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(50);
        }
        setState(() => _isLoadingMore = false);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollByPage(bool isPageUp) {
    if (_scrollController.hasClients) {
      final pageHeight = _scrollController.position.viewportDimension * 0.9;
      final target = isPageUp
          ? (_scrollController.offset + pageHeight).clamp(0.0, _scrollController.position.maxScrollExtent)
          : (_scrollController.offset - pageHeight).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<ChatProvider, ServerProvider, DebugLogger, PromptProvider>(
      builder: (context, chatProvider, serverProvider, debugLogger, promptProvider, _) {
        return Row(
          children: [
            // Sessions panel
            SizedBox(
              width: 240,
              child: _buildSessionsPanel(context, chatProvider),
            ),
            const VerticalDivider(width: 1),
            // Chat area
            Expanded(
              child: _buildChatArea(context, chatProvider),
            ),
            const VerticalDivider(width: 1),
            // Prompts panel
            SizedBox(
              width: 260,
              child: _buildPromptPanel(context, promptProvider),
            ),
            const VerticalDivider(width: 1),
            // Debug panel
            if (debugLogger.isVisible)
              SizedBox(
                width: 300,
                child: const DebugPanel(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPromptPanel(BuildContext context, PromptProvider provider) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.format_quote, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).savedPrompts,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (provider.prompts.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    onPressed: () => _showClearAllDialog(context, provider),
                    tooltip: AppLocalizations.of(context).clear,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: provider.prompts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 32, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context).noPromptsHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: provider.prompts.length,
                    itemBuilder: (context, index) {
                      final prompt = provider.prompts[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: InkWell(
                          onTap: () => _insertPrompt(prompt),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        prompt.text,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.dns, size: 11, color: Colors.grey[500]),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              prompt.serverName,
                                              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 14),
                                  onPressed: () => provider.deletePrompt(prompt.id),
                                  tooltip: AppLocalizations.of(context).delete,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _insertPrompt(SavedPrompt prompt) {
    final current = _messageController.text;
    final newText = current.isEmpty ? prompt.text : '$current\n${prompt.text}';
    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(offset: newText.length);
    _focusNode.requestFocus();
  }

  void _showClearAllDialog(BuildContext context, PromptProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).clearAllPrompts),
        content: Text(AppLocalizations.of(context).clearAllPromptsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              provider.clearAll();
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context).clear, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsPanel(BuildContext context, ChatProvider provider) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).sessionsList,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => provider.newSession(),
                  tooltip: AppLocalizations.of(context).newSession,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : provider.sessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            AppLocalizations.of(context).noSessions,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: provider.sessions.length,
                        itemBuilder: (context, index) {
                          final session = provider.sessions[index];
                          final isActive = provider.currentSessionId == session.id;
                          return ListTile(
                            dense: true,
                            selected: isActive,
                            title: Text(
                              session.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: session.updatedAt != null
                                ? Text(
                                    DateFormat('MM/dd HH:mm').format(session.updatedAt!),
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            onTap: () => provider.selectSession(session.id),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 16),
                              padding: EdgeInsets.zero,
                              onSelected: (value) {
                                if (value == 'delete') {
                                  provider.deleteSession(session.id);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea(BuildContext context, ChatProvider provider) {
    // Show login form if needed
    if (provider.needsLogin) {
      return _buildLoginForm(context, provider);
    }

    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Icon(Icons.smart_toy, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.server.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      widget.server.url,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (provider.currentSessionId != null)
                Chip(
                  label: Text(
                    provider.currentSessionId!.substring(0, 8),
                    style: const TextStyle(fontSize: 10),
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        // Messages area
        Expanded(
          child: provider.currentMessages.isEmpty
              ? _buildEmptyChat(context)
              : Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    const SingleActivator(LogicalKeyboardKey.pageUp): const _ScrollUpIntent(),
                    const SingleActivator(LogicalKeyboardKey.pageDown): const _ScrollDownIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _ScrollUpIntent: CallbackAction<_ScrollUpIntent>(
                        onInvoke: (_) => _scrollByPage(true),
                      ),
                      _ScrollDownIntent: CallbackAction<_ScrollDownIntent>(
                        onInvoke: (_) => _scrollByPage(false),
                      ),
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _visibleMessageCount,
                      itemBuilder: (context, index) {
                        final reversedIndex = _visibleMessageCount - 1 - index;
                        final message = provider.currentMessages[reversedIndex];
                        return _MessageBubble(message: message);
                      },
                    ),
                  ),
                ),
        ),
        // Typing indicator
        if (provider.isSending)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).thinking,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        // Input area
        _buildInputArea(context, provider),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context, ChatProvider provider) {
    final usernameController = TextEditingController(text: widget.server.username ?? '');
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoggingIn = false;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context).loginRequired,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).loginPrompt(widget.server.name),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).username,
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context).enterUsername;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).password,
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context).enterPassword;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                StatefulBuilder(
                  builder: (context, setState) {
                    return FilledButton.icon(
                      onPressed: isLoggingIn
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setState(() => isLoggingIn = true);
                              final success = await provider.retryLogin(
                                usernameController.text.trim(),
                                passwordController.text.trim(),
                              );
                              setState(() => isLoggingIn = false);
                              if (!success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(provider.error ?? AppLocalizations.of(context).loginFailed),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      icon: isLoggingIn
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(isLoggingIn ? AppLocalizations.of(context).loggingIn : AppLocalizations.of(context).login),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    );
                  },
                ),
                if (provider.error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.error!,
                            style: TextStyle(color: Colors.red[700], fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChat(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).startConversation,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).typeToBegin(widget.server.name),
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Model selector row
          _buildModelSelector(context, provider),
          const SizedBox(height: 8),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).typeMessage,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  maxLines: 6,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  onSubmitted: (_) => _sendMessage(provider),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                onPressed: provider.isSending ? null : () => _sendMessage(provider),
                child: const Icon(Icons.send, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(BuildContext context, ChatProvider provider) {
    if (provider.modelGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    // Build a flat list of all models for the dropdown
    final allModels = <_ModelEntry>[];
    for (final group in provider.modelGroups) {
      for (final model in group.models) {
        allModels.add(_ModelEntry(
          modelId: model.id,
          providerKey: group.providerKey,
          providerName: group.provider,
          label: model.label,
        ));
      }
    }

    if (allModels.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.memory, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(AppLocalizations.of(context).model, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: provider.selectedModel,
              isDense: true,
              isExpanded: true,
              hint: Text(AppLocalizations.of(context).selectModel, style: const TextStyle(fontSize: 12)),
              items: allModels.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.modelId,
                  child: Text(
                    '${entry.providerName}: ${entry.label}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  final entry = allModels.firstWhere((e) => e.modelId == value);
                  provider.selectModel(value, entry.providerKey);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  void _sendMessage(ChatProvider provider) {
    final text = _messageController.text.trim();
    if (text.isEmpty || provider.isSending) return;

    _messageController.clear();
    _scrollToBottom();
    provider.sendMessage(text);
    _scrollToBottom();
    _focusNode.requestFocus();
  }

}

class _ScrollUpIntent extends Intent {
  const _ScrollUpIntent();
}

class _ScrollDownIntent extends Intent {
  const _ScrollDownIntent();
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: message.isError ? Colors.red[100] : Colors.blue[100],
              child: Icon(
                message.isError ? Icons.error_outline : Icons.smart_toy,
                size: 16,
                color: message.isError ? Colors.red : Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : message.isError
                        ? Colors.red[50]
                        : Colors.grey[100],
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : null,
                  bottomLeft: !isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14, color: Colors.black87),
                        code: TextStyle(
                          backgroundColor: Colors.grey[200],
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        blockquote: TextStyle(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Colors.grey[400]!, width: 3),
                          ),
                        ),
                        blockquotePadding: const EdgeInsets.only(left: 12),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: TextStyle(
                      color: isUser ? Colors.white70 : Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.person, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelEntry {
  final String modelId;
  final String providerKey;
  final String providerName;
  final String label;

  _ModelEntry({
    required this.modelId,
    required this.providerKey,
    required this.providerName,
    required this.label,
  });
}
