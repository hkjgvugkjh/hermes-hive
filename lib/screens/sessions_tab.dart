import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/server_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/debug_logger.dart';
import '../providers/prompt_provider.dart';
import '../l10n/app_localizations.dart';

class SessionsTab extends StatefulWidget {
  final ServerConfig server;

  const SessionsTab({super.key, required this.server});

  @override
  State<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<SessionsTab> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  static const int _initialMessageCount = 20;
  static const int _loadBatchSize = 30;
  int _visibleMessageCount = _initialMessageCount;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      final promptProvider = context.read<PromptProvider>();
      chatProvider.setPromptProvider(promptProvider);
      chatProvider.loadSessions();
      chatProvider.loadModelGroups();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ChatProvider>().refreshSessions();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 80 &&
        !_isLoadingMore && _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    final provider = context.read<ChatProvider>();
    final totalMessages = provider.currentMessages.length;

    if (totalMessages > _visibleMessageCount) {
      setState(() {
        _isLoadingMore = true;
        _visibleMessageCount = (_visibleMessageCount + _loadBatchSize).clamp(0, totalMessages);
        if (_visibleMessageCount >= totalMessages) {
          _hasMoreMessages = false;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.offset + 60);
        }
        setState(() => _isLoadingMore = false);
      });
    } else {
      setState(() => _hasMoreMessages = false);
    }
  }

  void _resetPagination() {
    setState(() {
      _visibleMessageCount = _initialMessageCount;
      _hasMoreMessages = true;
      _isLoadingMore = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<ChatProvider, ServerProvider, DebugLogger, PromptProvider>(
      builder: (context, chatProvider, serverProvider, debugLogger, promptProvider, _) {
        return Row(
          children: [
            // Session list sidebar
            SizedBox(
              width: 200,
              child: _buildSessionList(context, chatProvider),
            ),
            const VerticalDivider(width: 1),
            // Chat area
            Expanded(
              child: _buildChatArea(context, chatProvider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSessionList(BuildContext context, ChatProvider provider) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text('会话', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => provider.refreshSessions(),
                  tooltip: '刷新',
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () {
                    _resetPagination();
                    provider.newSession();
                  },
                  tooltip: l10n.newSession,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : provider.displaySessions.isEmpty
                    ? Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey[500])))
                    : ListView.builder(
                        itemCount: provider.displaySessions.length,
                        itemBuilder: (context, index) {
                          final session = provider.displaySessions[index];
                          final isActive = provider.currentSessionId == session.id;
                          return _buildSessionTile(context, provider, session, isActive);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(BuildContext context, ChatProvider provider, HermesSession session, bool isActive) {
    return ListTile(
      dense: true,
      selected: isActive,
      leading: Icon(
        isActive ? Icons.chat : Icons.chat_bubble_outline,
        size: 16,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(session.title, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
      subtitle: session.updatedAt != null
          ? Text('${session.updatedAt!.month}/${session.updatedAt!.day} ${session.updatedAt!.hour}:${session.updatedAt!.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10))
          : null,
      onTap: () {
        _resetPagination();
        provider.selectSession(session.id);
      },
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        padding: EdgeInsets.zero,
        onSelected: (value) {
          if (value == 'delete') {
            provider.deleteSession(session.id);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildChatArea(BuildContext context, ChatProvider provider) {
    if (provider.needsLogin) {
      return _buildLoginForm(context, provider);
    }

    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
          child: Row(
            children: [
              Icon(Icons.smart_toy, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.server.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(widget.server.url, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (provider.currentSessionId != null)
                Chip(
                  label: Text(provider.currentSessionId!.substring(0, 8), style: const TextStyle(fontSize: 10)),
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
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _visibleMessageCount + (_hasMoreMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_hasMoreMessages && index == _visibleMessageCount) {
                      return _buildLoadingIndicator();
                    }
                    final reversedIndex = _visibleMessageCount - 1 - index;
                    final message = provider.currentMessages[reversedIndex];
                    return _MessageBubble(message: message);
                  },
                ),
        ),
        // Typing indicator
        if (provider.isSending)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 8),
                Text('AI 正在思考...', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
        // Input area
        _buildInputArea(context, provider),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 8),
          Text('加载更多...', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
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
          Text(AppLocalizations.of(context).startConversation, style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[300]!))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(provider),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(provider),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  void _sendMessage(ChatProvider provider) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    _resetPagination();
    provider.sendMessage(text);
    _scrollToBottom();
  }

  Widget _buildLoginForm(BuildContext context, ChatProvider provider) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    return Center(
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('需要登录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                provider.retryLogin(usernameController.text, passwordController.text);
              },
              child: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
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
            CircleAvatar(radius: 14, child: Icon(Icons.smart_toy, size: 16)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Theme.of(context).colorScheme.primary : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.content,
                style: TextStyle(color: isUser ? Colors.white : Colors.black87),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
          ],
        ],
      ),
    );
  }
}
