import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import '../services/data_service.dart';
import 'pdf_viewer_screen.dart';

class InstanceSelectionScreen extends StatefulWidget {
  const InstanceSelectionScreen({super.key, required this.instance});

  final StructureInstance instance;

  @override
  State<InstanceSelectionScreen> createState() => _InstanceSelectionScreenState();
}

class _InstanceSelectionScreenState extends State<InstanceSelectionScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final latest = await context.read<DataService>().getInstance(widget.instance.id);
    final instance = latest ?? widget.instance;
    final pdfs = await context.read<DataService>().getPdfs();
    final tags = await context.read<DataService>().getTags();
    final selections = await context.read<DataService>().getInstanceSelections(instance.id);
    return {
      'instance': instance,
      'template': instance.templateSnapshot,
      'pdfs': pdfs,
      'tags': tags,
      'selections': selections,
    };
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadData());
  }

  Future<void> _selectPdfsForSlot(String slotId, List<String> requiredTags, List<String> currentSelection) async {
    final candidates = await context.read<DataService>().findPdfsByTags(requiredTags);
    if (!mounted) return;

    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final tempSelection = <String>{...currentSelection};
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (candidates.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum PDF corresponde às tags exigidas para esta sub-estrutura.'),
              );
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: Column(
                  children: [
                    const ListTile(title: Text('Selecionar PDFs para o slot')),
                    Expanded(
                      child: ListView(
                        children: candidates
                            .map(
                              (pdf) => CheckboxListTile(
                                value: tempSelection.contains(pdf.id),
                                title: Text(pdf.title),
                                onChanged: (checked) {
                                  setModalState(() {
                                    if (checked == true) {
                                      tempSelection.add(pdf.id);
                                    } else {
                                      tempSelection.remove(pdf.id);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context, <String>[]),
                            child: const Text('Limpar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final ordered = candidates.where((pdf) => tempSelection.contains(pdf.id)).map((pdf) => pdf.id).toList();
                              Navigator.pop(context, ordered);
                            },
                            child: const Text('Confirmar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;

    await context.read<DataService>().updateInstanceSelection(widget.instance.id, slotId, selected);
    await _refresh();
  }

  Future<void> _reorderSlotSelection(String slotId, List<String> selectedIds, int from, int to) async {
    final updated = List<String>.from(selectedIds);
    final item = updated.removeAt(from);
    updated.insert(to, item);
    await context.read<DataService>().updateInstanceSelection(widget.instance.id, slotId, updated);
    await _refresh();
  }

  Future<void> _removePdfFromSlot(String slotId, List<String> selectedIds, String pdfId) async {
    final updated = List<String>.from(selectedIds)..remove(pdfId);
    await context.read<DataService>().updateInstanceSelection(widget.instance.id, slotId, updated);
    await _refresh();
  }

  Future<void> _renameInstance(StructureInstance instance) async {
    final controller = TextEditingController(text: instance.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear instância'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    await context.read<DataService>().renameInstance(instance.id, newName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Instância renomeada.')));
    await _refresh();
  }

  Future<void> _deleteInstance(StructureInstance instance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir instância'),
        content: Text('Deseja excluir "${instance.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await context.read<DataService>().deleteInstance(instance.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _clearAllSelections(StructureInstance instance) async {
    await context.read<DataService>().clearAllInstanceSelections(instance.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleções limpas.')));
    await _refresh();
  }

  Future<void> _openSelectedPdf(PdfFile pdf) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfFile: pdf)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            final instance = snapshot.data?['instance'] as StructureInstance?;
            return Text(instance?.name ?? widget.instance.name);
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Duplicar instância',
            onPressed: () async {
              final current = await context.read<DataService>().getInstance(widget.instance.id);
              if (current == null) return;
              await context.read<DataService>().duplicateInstance(current);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Instância duplicada com sucesso.')));
            },
            icon: const Icon(Icons.copy),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ações da instância',
            onSelected: (value) async {
              final current = await context.read<DataService>().getInstance(widget.instance.id);
              if (current == null || !mounted) return;
              if (value == 'rename') {
                await _renameInstance(current);
              } else if (value == 'clear') {
                await _clearAllSelections(current);
              } else if (value == 'delete') {
                await _deleteInstance(current);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'rename',
                child: ListTile(leading: Icon(Icons.edit), title: Text('Renomear')),
              ),
              PopupMenuItem<String>(
                value: 'clear',
                child: ListTile(leading: Icon(Icons.cleaning_services_outlined), title: Text('Limpar seleções')),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir')),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final template = snapshot.data?['template'] as StructureTemplate?;
          final instance = snapshot.data?['instance'] as StructureInstance?;
          if (template == null || instance == null) {
            return const Center(child: Text('Instância não encontrada.'));
          }

          final pdfs = (snapshot.data?['pdfs'] as List<PdfFile>?) ?? [];
          final tags = (snapshot.data?['tags'] as List<Tag>?) ?? [];
          final selections = (snapshot.data?['selections'] as Map<String, List<String>>?) ?? {};

          return Column(
            children: [
              SwitchListTile(
                title: const Text('Marcar como concluída'),
                value: instance.isCompleted,
                onChanged: (value) async {
                  await context.read<DataService>().updateInstanceMeta(instanceId: instance.id, isCompleted: value);
                  await _refresh();
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: template.slots.length,
                  itemBuilder: (context, index) {
                    final slot = template.slots[index];
                    final selectedPdfIds = selections[slot.id] ?? <String>[];
                    final selectedPdfs = selectedPdfIds
                        .map(
                          (id) => pdfs.firstWhere(
                            (p) => p.id == id,
                            orElse: () => PdfFile(id: '', title: 'Desconhecido', path: ''),
                          ),
                        )
                        .where((pdf) => pdf.id.isNotEmpty)
                        .toList();

                    final requiredTags = slot.requiredTagIds
                        .map((id) => tags.firstWhere((t) => t.id == id, orElse: () => Tag(id: id, name: id)).name)
                        .join(', ');

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(slot.name),
                              subtitle: Text('Tags exigidas: $requiredTags'),
                              trailing: OutlinedButton(
                                onPressed: () => _selectPdfsForSlot(slot.id, slot.requiredTagIds, selectedPdfIds),
                                child: const Text('Selecionar PDFs'),
                              ),
                            ),
                            if (selectedPdfs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Nenhum PDF selecionado.'),
                              )
                            else
                              ...List.generate(selectedPdfs.length, (pdfIndex) {
                                final pdf = selectedPdfs[pdfIndex];
                                return ListTile(
                                  dense: true,
                                  title: Text('${pdfIndex + 1}. ${pdf.title}'),
                                  leading: IconButton(
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () => _openSelectedPdf(pdf),
                                  ),
                                  trailing: Wrap(
                                    spacing: 2,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_upward),
                                        onPressed: pdfIndex == 0
                                            ? null
                                            : () => _reorderSlotSelection(slot.id, selectedPdfIds, pdfIndex, pdfIndex - 1),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_downward),
                                        onPressed: pdfIndex == selectedPdfs.length - 1
                                            ? null
                                            : () => _reorderSlotSelection(slot.id, selectedPdfIds, pdfIndex, pdfIndex + 1),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _removePdfFromSlot(slot.id, selectedPdfIds, pdf.id),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
