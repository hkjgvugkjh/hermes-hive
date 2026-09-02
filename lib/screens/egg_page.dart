import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/egg_models.dart';
import '../../providers/egg_provider.dart';
import '../../l10n/app_localizations.dart';

/// Page for managing free model combinations ("Egg of Today")
class EggPage extends StatefulWidget {
  const EggPage({super.key});

  @override
  State<EggPage> createState() => _EggPageState();
}

class _EggPageState extends State<EggPage> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final Set<String> _selectedModelIds = {};
  bool _isEditingConfig = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final eggProvider = context.read<EggProvider>();
      eggProvider.init();
      _urlController.text = eggProvider.config.apiUrl;
      _apiKeyController.text = eggProvider.config.apiKey;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.egg),
            const SizedBox(width: 8),
            Text(l10n.eggOfToday),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.openRouterConfig,
            onPressed: () {
              setState(() {
                _isEditingConfig = !_isEditingConfig;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshAll,
            onPressed: () {
              context.read<EggProvider>().refreshAvailability();
            },
          ),
        ],
      ),
      body: Consumer<EggProvider>(
        builder: (context, eggProvider, _) {
          return Row(
            children: [
              // Left panel: Configuration + Free Models
              SizedBox(
                width: 400,
                child: Column(
                  children: [
                    // OpenRouter Configuration
                    if (_isEditingConfig) _buildConfigPanel(context, eggProvider),
                    // Free models section
                    Expanded(
                      child: _buildFreeModelsPanel(context, eggProvider),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // Right panel: Saved Combinations
              Expanded(
                child: _buildCombinationsPanel(context, eggProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigPanel(BuildContext context, EggProvider eggProvider) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.openRouterConfig,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() {
                      _isEditingConfig = false;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: l10n.apiUrl,
                hintText: 'https://openrouter.ai/api/v1',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                hintText: 'sk-or-v1-...',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final newConfig = OpenRouterConfig(
                      apiUrl: _urlController.text.trim(),
                      apiKey: _apiKeyController.text.trim(),
                    );
                    eggProvider.updateConfig(newConfig);
                    setState(() {
                      _isEditingConfig = false;
                    });
                  },
                  icon: const Icon(Icons.save, size: 16),
                  label: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreeModelsPanel(BuildContext context, EggProvider eggProvider) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                l10n.freeModels,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              if (eggProvider.freeModels.isNotEmpty)
                Chip(
                  label: Text('${eggProvider.freeModels.length}'),
                  visualDensity: VisualDensity.compact,
                ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: eggProvider.isLoading
                    ? null
                    : () {
                        eggProvider.fetchFreeModels();
                      },
                icon: eggProvider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download, size: 16),
                label: Text(l10n.fetchModels),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Error message
        if (eggProvider.error != null)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eggProvider.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        // Models list
        Expanded(
          child: eggProvider.freeModels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.model_training,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        l10n.noFreeModels,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: eggProvider.freeModels.length,
                  itemBuilder: (context, index) {
                    final model = eggProvider.freeModels[index];
                    final isSelected =
                        _selectedModelIds.contains(model.id);
                    return ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedModelIds.add(model.id);
                            } else {
                              _selectedModelIds.remove(model.id);
                            }
                          });
                        },
                      ),
                      title: Text(
                        model.name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${model.provider} • ${model.contextLength}K context',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600]),
                      ),
                      trailing: eggProvider.hasAvailabilityInfo(model.id)
                          ? Icon(
                              eggProvider.isModelAvailableCached(model.id)
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 16,
                              color: eggProvider.isModelAvailableCached(model.id)
                                  ? Colors.green
                                  : Colors.red,
                            )
                          : null,
                    );
                  },
                ),
        ),
        // Create combination bar
        if (_selectedModelIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Text(l10n.selectedCount(_selectedModelIds.length)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    _showCreateCombinationDialog(context, eggProvider);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.createCombination),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCombinationsPanel(BuildContext context, EggProvider eggProvider) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                l10n.modelCombinations,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              if (eggProvider.combinations.isNotEmpty)
                Chip(
                  label: Text('${eggProvider.combinations.length}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: eggProvider.combinations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.layers,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        l10n.noCombinations,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: eggProvider.combinations.length,
                  itemBuilder: (context, index) {
                    final combination = eggProvider.combinations[index];
                    return _buildCombinationCard(
                        context, eggProvider, combination);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCombinationCard(BuildContext context, EggProvider eggProvider,
      ModelCombination combination) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    combination.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: l10n.checkAvailability,
                  onPressed: () {
                    eggProvider.checkCombinationAvailability(combination);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: l10n.delete,
                  onPressed: () {
                    _confirmDeleteCombination(context, eggProvider, combination);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
            spacing: 6,
            runSpacing: 6,
            children: combination.modelIds.map((modelId) {
            final isAvailable =
                eggProvider.isModelAvailableCached(modelId);
            return Chip(
              label: Text(
                modelId.split('/').last,
                style: const TextStyle(fontSize: 11),
              ),
              avatar: eggProvider.hasAvailabilityInfo(modelId)
                  ? Icon(
                      isAvailable ? Icons.check : Icons.close,
                      size: 14,
                      color: isAvailable ? Colors.green : Colors.red,
                    )
                  : null,
              visualDensity: VisualDensity.compact,
            );
            }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateCombinationDialog(
      BuildContext context, EggProvider eggProvider) {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.createCombination),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.combinationName,
            hintText: l10n.combinationNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final combination = ModelCombination(
                  id: const Uuid().v4(),
                  name: name,
                  modelIds: _selectedModelIds.toList(),
                );
                eggProvider.addCombination(combination);
                setState(() {
                  _selectedModelIds.clear();
                });
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCombination(BuildContext context,
      EggProvider eggProvider, ModelCombination combination) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteCombination),
        content: Text(l10n.deleteCombinationConfirm(combination.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              eggProvider.deleteCombination(combination.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
