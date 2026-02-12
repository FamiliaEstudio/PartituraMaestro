import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/structure_template.dart';
import '../models/tag.dart';
import '../services/data_service.dart';

class CreateTemplateScreen extends StatefulWidget {
  const CreateTemplateScreen({super.key});

  @override
  State<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final DataService _dataService = DataService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<SubStructureSlot> _slots = [];
  List<Tag> _allTags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _dataService.getTags();
    if (!mounted) return;
    setState(() {
      _allTags = tags;
    });
  }

  void _addSlot() {
    final slotNameController = TextEditingController();
    final selectedTagIds = <String>[];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Nova Sub-estrutura'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: slotNameController,
                      decoration: const InputDecoration(labelText: 'Nome (ex: Entrada)'),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Tags exigidas:'),
                    ),
                    ..._allTags.map(
                      (tag) => CheckboxListTile(
                        value: selectedTagIds.contains(tag.id),
                        title: Text(tag.name),
                        onChanged: (value) {
                          setModalState(() {
                            if (value == true) {
                              selectedTagIds.add(tag.id);
                            } else {
                              selectedTagIds.remove(tag.id);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (slotNameController.text.trim().isNotEmpty) {
                      setState(() {
                        _slots.add(
                          SubStructureSlot(
                            id: const Uuid().v4(),
                            name: slotNameController.text.trim(),
                            requiredTagIds: List.from(selectedTagIds),
                          ),
                        );
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveTemplate() async {
    if (_formKey.currentState!.validate()) {
      final template = StructureTemplate(
        id: const Uuid().v4(),
        name: _nameController.text,
        slots: _slots,
      );
      await _dataService.addTemplate(template);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Nova Estrutura')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome da Estrutura (ex: Missa)'),
                validator: (value) => value!.isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 20),
              const Text('Sub-estruturas (Partes):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: ListView.builder(
                  itemCount: _slots.length,
                  itemBuilder: (context, index) {
                    final slot = _slots[index];
                    final tagNames = slot.requiredTagIds
                        .map(
                          (id) => _allTags.firstWhere((tag) => tag.id == id, orElse: () => Tag(id: id, name: id)).name,
                        )
                        .join(', ');

                    return ListTile(
                      title: Text(slot.name),
                      subtitle: Text('Tags: $tagNames'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          setState(() {
                            _slots.removeAt(index);
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(
                onPressed: _addSlot,
                child: const Text('Adicionar Sub-estrutura'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveTemplate,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text('Salvar Estrutura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
