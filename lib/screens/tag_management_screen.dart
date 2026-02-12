import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../services/data_service.dart';

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  final DataService _dataService = DataService();
  final TextEditingController _controller = TextEditingController();
  late Future<List<Tag>> _tagsFuture;

  @override
  void initState() {
    super.initState();
    _tagsFuture = _dataService.getTags();
  }

  Future<void> _reload() async {
    setState(() {
      _tagsFuture = _dataService.getTags();
    });
    widget.onDataChanged();
  }

  Future<void> _addTag() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    await _dataService.addTag(Tag(id: const Uuid().v4(), name: name));
    _controller.clear();
    await _reload();
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
    await _dataService.updateTag(tag.id, value);
    await _reload();
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover tag'),
        content: Text('A tag "${tag.name}" será removida dos PDFs e slots vinculados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ),
    );

    if (confirm != true) return;
    await _dataService.deleteTag(tag.id);
    await _reload();
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
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Tag>>(
                future: _tagsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final tags = snapshot.data ?? [];
                  if (tags.isEmpty) {
                    return const Center(child: Text('Nenhuma tag criada.'));
                  }

                  return ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return ListTile(
                        leading: const Icon(Icons.local_offer),
                        title: Text(tag.name),
                        subtitle: Text('ID: ${tag.id}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(onPressed: () => _editTag(tag), icon: const Icon(Icons.edit_outlined)),
                            IconButton(onPressed: () => _deleteTag(tag), icon: const Icon(Icons.delete_outline)),
                          ],
                        ),
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
