import 'package:flutter/material.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import '../services/data_service.dart';
import 'package:uuid/uuid.dart';

class CreateTemplateScreen extends StatefulWidget {
  @override
  _CreateTemplateScreenState createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<SubStructureSlot> _slots = [];
  final DataService _dataService = DataService();

  Future<void> _addSlot() async {
    final nameController = TextEditingController();
    List<String> selectedTagIds = [];
    final allTags = _dataService.getTags();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Adicionar Slot'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nome do Slot (ex: Entrada)'),
                    ),
                    const SizedBox(height: 10),
                    const Text('Tags Requeridas:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...allTags.map((tag) {
                      return CheckboxListTile(
                        title: Text(tag.name),
                        value: selectedTagIds.contains(tag.id),
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            if (value == true) {
                              selectedTagIds.add(tag.id);
                            } else {
                              selectedTagIds.remove(tag.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      setState(() {
                        _slots.add(SubStructureSlot(
                          id: const Uuid().v4(),
                          name: nameController.text,
                          requiredTagIds: selectedTagIds,
                        ));
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

  void _saveTemplate() {
    if (_formKey.currentState!.validate()) {
      final template = StructureTemplate(
        id: const Uuid().v4(),
        name: _nameController.text,
        slots: _slots,
      );
      _dataService.addTemplate(template);
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
                    // Recuperar nomes das tags para exibição
                    final tagNames = slot.requiredTagIds
                        .map((id) => _dataService.getTag(id)?.name ?? id)
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
