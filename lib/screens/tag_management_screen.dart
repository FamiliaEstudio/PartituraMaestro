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

  void _addTag() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    _dataService.addTag(Tag(id: const Uuid().v4(), name: name));
    _controller.clear();
    setState(() {});
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tags = _dataService.getTags();

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
              child: tags.isEmpty
                  ? const Center(child: Text('Nenhuma tag criada.'))
                  : ListView.builder(
                      itemCount: tags.length,
                      itemBuilder: (context, index) {
                        final tag = tags[index];
                        return ListTile(
                          leading: const Icon(Icons.local_offer),
                          title: Text(tag.name),
                          subtitle: Text('ID: ${tag.id}'),
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
