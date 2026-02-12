import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/usecases/create_template.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import '../services/data_service.dart';

class CreateTemplateScreen extends StatefulWidget {
  const CreateTemplateScreen({super.key, this.template});

  final StructureTemplate? template;

  @override
  State<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
    final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<SubStructureSlot> _slots = [];
  List<Tag> _allTags = [];

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.template?.name ?? '';
    if (_isEditing) {
      _slots.addAll(
        widget.template!.slots
            .map((slot) => SubStructureSlot(id: slot.id, name: slot.name, requiredTagIds: List<String>.from(slot.requiredTagIds))),
      );
    }
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await context.read<DataService>().getTags();
    if (!mounted) return;
    setState(() {
      _allTags = tags;
    });
  }

  Future<void> _openSlotDialog({SubStructureSlot? existing, int? editIndex}) async {
    final slotNameController = TextEditingController(text: existing?.name ?? '');
    final selectedTagIds = List<String>.from(existing?.requiredTagIds ?? const []);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(existing == null ? 'Nova Sub-estrutura' : 'Editar Sub-estrutura'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: slotNameController,
                      decoration: const InputDecoration(labelText: 'Nome (ex: Entrada)'),
                    ),
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft, child: Text('Tags exigidas:')),
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
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    final slotName = slotNameController.text.trim();
                    if (slotName.isEmpty) return;
                    final duplicate = _slots.any((slot) {
                      if (editIndex != null && _slots[editIndex].id == slot.id) return false;
                      return slot.name.toLowerCase() == slotName.toLowerCase();
                    });
                    if (duplicate) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Não é permitido nome de sub-estrutura duplicado no mesmo template.')),
                      );
                      return;
                    }

                    setState(() {
                      final newSlot = SubStructureSlot(
                        id: existing?.id ?? const Uuid().v4(),
                        name: slotName,
                        requiredTagIds: List<String>.from(selectedTagIds),
                      );
                      if (editIndex != null) {
                        _slots[editIndex] = newSlot;
                      } else {
                        _slots.add(newSlot);
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: Text(existing == null ? 'Adicionar' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos uma sub-estrutura.')));
      return;
    }

    final template = StructureTemplate(
      id: widget.template?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      slots: List<SubStructureSlot>.from(_slots),
    );

    if (_isEditing) {
      await context.read<DataService>().updateTemplate(template);
    } else {
      await context.read<CreateTemplate>()(template);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Estrutura' : 'Criar Nova Estrutura')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome da Estrutura (ex: Missa)'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 20),
              const Text('Sub-estruturas (Partes):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _slots.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _slots.removeAt(oldIndex);
                      _slots.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final slot = _slots[index];
                    final tagNames = slot.requiredTagIds
                        .map((id) => _allTags.firstWhere((tag) => tag.id == id, orElse: () => Tag(id: id, name: id)).name)
                        .join(', ');

                    return ListTile(
                      key: ValueKey(slot.id),
                      title: Text(slot.name),
                      subtitle: Text('Tags: $tagNames'),
                      leading: const Icon(Icons.drag_handle),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _openSlotDialog(existing: slot, editIndex: index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                _slots.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(onPressed: () => _openSlotDialog(), child: const Text('Adicionar Sub-estrutura')),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveTemplate,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: Text(_isEditing ? 'Salvar Alterações' : 'Salvar Estrutura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
