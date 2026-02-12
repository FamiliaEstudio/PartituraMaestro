import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../services/data_service.dart';

class _TagViewData {
  final Tag tag;
  final TagUsageStats usage;

  const _TagViewData({required this.tag, required this.usage});
}

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
    final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<_TagViewData>> _tagsFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tagsFuture = _loadTagData();
  }

  Future<List<_TagViewData>> _loadTagData() async {
    final tags = await context.read<DataService>().getTags();
    final usageByTag = await context.read<DataService>().getTagUsageStats();

    final items = tags
        .map(
          (tag) => _TagViewData(
            tag: tag,
            usage: usageByTag[tag.id] ?? const TagUsageStats(pdfCount: 0, slotCount: 0),
          ),
        )
        .toList();

    items.sort(
      (a, b) => _dataService
          .normalizeTagName(a.tag.name)
          .compareTo(context.read<DataService>().normalizeTagName(b.tag.name)),
    );
    return items;
  }

  Future<void> _reload() async {
    setState(() {
      _tagsFuture = _loadTagData();
    });
    widget.onDataChanged();
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addTag() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    try {
      await context.read<DataService>().addTag(Tag(id: const Uuid().v4(), name: name));
      _controller.clear();
      await _reload();
    } on TagNameConflictException catch (error) {
      _showInfo(error.message);
    }
  }

  Future<void> _editTag(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar tag'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );

    if (value == null || value.isEmpty) return;
    try {
      await context.read<DataService>().updateTag(tag.id, value);
      await _reload();
    } on TagNameConflictException catch (error) {
      _showInfo(error.message);
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final usage = await context.read<DataService>().getTagUsage(tag.id);
    final tags = await context.read<DataService>().getTags();
    final replacementOptions = tags.where((t) => t.id != tag.id).toList();

    if (!mounted) return;

    final result = await showDialog<_DeleteTagResult>(
      context: context,
      builder: (context) => _DeleteTagDialog(
        tag: tag,
        usage: usage,
        replacementOptions: replacementOptions,
      ),
    );

    if (result == null) return;

    await context.read<DataService>().deleteTagWithStrategy(
      tagId: tag.id,
      replacementTagId: result.replacementTagId,
    );
    await _reload();
  }

  Map<String, List<_TagViewData>> _groupAlphabetically(List<_TagViewData> tags) {
    final filtered = tags.where((item) {
      final normalizedName = context.read<DataService>().normalizeTagName(item.tag.name);
      final normalizedQuery = context.read<DataService>().normalizeTagName(_searchQuery);
      return normalizedQuery.isEmpty || normalizedName.contains(normalizedQuery);
    }).toList();

    final grouped = <String, List<_TagViewData>>{};
    for (final item in filtered) {
      final normalized = context.read<DataService>().normalizeTagName(item.tag.name, caseFold: false);
      final firstChar = normalized.isEmpty ? '#' : normalized.substring(0, 1).toUpperCase();
      final key = RegExp(r'[A-Z]').hasMatch(firstChar) ? firstChar : '#';
      grouped.putIfAbsent(key, () => []).add(item);
    }

    for (final entry in grouped.entries) {
      entry.value.sort(
        (a, b) => _dataService
            .normalizeTagName(a.tag.name)
            .compareTo(context.read<DataService>().normalizeTagName(b.tag.name)),
      );
    }

    final orderedKeys = grouped.keys.toList()..sort();
    return {for (final key in orderedKeys) key: grouped[key]!};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Nova tag',
                      hintText: 'Ex: Canto de abertura',
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar tags',
                hintText: 'Digite para filtrar',
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<_TagViewData>>(
                future: _tagsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final tags = snapshot.data ?? [];
                  final grouped = _groupAlphabetically(tags);
                  if (grouped.isEmpty) {
                    return Center(
                      child: Text(
                        tags.isEmpty ? 'Nenhuma tag criada.' : 'Nenhuma tag encontrada para a busca.',
                      ),
                    );
                  }

                  final sections = grouped.entries.toList();
                  return ListView.builder(
                    itemCount: sections.length,
                    itemBuilder: (context, sectionIndex) {
                      final section = sections[sectionIndex];
                      return _TagSection(
                        letter: section.key,
                        items: section.value,
                        onEdit: _editTag,
                        onDelete: _deleteTag,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({
    required this.letter,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final String letter;
  final List<_TagViewData> items;
  final ValueChanged<Tag> onEdit;
  final ValueChanged<Tag> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            letter,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...items.map(
          (item) => ListTile(
            leading: const Icon(Icons.local_offer),
            title: Text(item.tag.name),
            subtitle: Text('PDFs: ${item.usage.pdfCount} • Slots: ${item.usage.slotCount}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(onPressed: () => onEdit(item.tag), icon: const Icon(Icons.edit_outlined)),
                IconButton(onPressed: () => onDelete(item.tag), icon: const Icon(Icons.delete_outline)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteTagResult {
  final String? replacementTagId;

  const _DeleteTagResult({this.replacementTagId});
}

class _DeleteTagDialog extends StatefulWidget {
  const _DeleteTagDialog({
    required this.tag,
    required this.usage,
    required this.replacementOptions,
  });

  final Tag tag;
  final TagUsageStats usage;
  final List<Tag> replacementOptions;

  @override
  State<_DeleteTagDialog> createState() => _DeleteTagDialogState();
}

class _DeleteTagDialogState extends State<_DeleteTagDialog> {
  bool _replace = false;
  String? _selectedReplacementId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excluir tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A tag "${widget.tag.name}" está em ${widget.usage.pdfCount} PDFs e ${widget.usage.slotCount} slots.'),
          const SizedBox(height: 12),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: false,
            groupValue: _replace,
            title: const Text('Remover das referências'),
            subtitle: const Text('A tag será apagada dos PDFs e slots que a usam.'),
            onChanged: (value) {
              setState(() {
                _replace = value ?? false;
              });
            },
          ),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: true,
            groupValue: _replace,
            title: const Text('Substituir por outra tag'),
            subtitle: const Text('As referências serão migradas para outra tag.'),
            onChanged: widget.replacementOptions.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _replace = value ?? false;
                    });
                  },
          ),
          if (_replace)
            DropdownButtonFormField<String>(
              value: _selectedReplacementId,
              decoration: const InputDecoration(labelText: 'Tag substituta'),
              items: widget.replacementOptions
                  .map((tag) => DropdownMenuItem(value: tag.id, child: Text(tag.name)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedReplacementId = value;
                });
              },
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_replace && _selectedReplacementId == null) return;
            Navigator.pop(
              context,
              _DeleteTagResult(replacementTagId: _replace ? _selectedReplacementId : null),
            );
          },
          child: const Text('Confirmar exclusão'),
        ),
      ],
    );
  }
}
