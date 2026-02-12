import 'package:flutter/material.dart';

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
  final DataService _dataService = DataService();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final latest = await _dataService.getInstance(widget.instance.id);
    final instance = latest ?? widget.instance;
    final pdfs = await _dataService.getPdfs();
    final tags = await _dataService.getTags();
    final selections = await _dataService.getInstanceSelections(instance.id);
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

  Future<void> _selectPdfForSlot(String slotId, List<String> requiredTags) async {
    final candidates = await _dataService.findPdfsByTags(requiredTags);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        if (candidates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum PDF corresponde às tags exigidas para esta sub-estrutura.'),
          );
        }

        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Remover seleção deste slot'),
              onTap: () async {
                await _dataService.clearInstanceSelection(widget.instance.id, slotId);
                if (!context.mounted) return;
                Navigator.pop(context);
                await _refresh();
              },
            ),
            ...candidates.map(
              (pdf) => ListTile(
                title: Text(pdf.title),
                onTap: () async {
                  await _dataService.updateInstanceSelection(widget.instance.id, slotId, pdf.id);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await _refresh();
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSelectedPdf(PdfFile pdf) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfFile: pdf)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.instance.name),
        actions: [
          IconButton(
            tooltip: 'Duplicar instância',
            onPressed: () async {
              final current = await _dataService.getInstance(widget.instance.id);
              if (current == null) return;
              await _dataService.duplicateInstance(current);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Instância duplicada com sucesso.')));
            },
            icon: const Icon(Icons.copy),
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
          final selections = (snapshot.data?['selections'] as Map<String, String?>?) ?? {};

          return Column(
            children: [
              SwitchListTile(
                title: const Text('Marcar como concluída'),
                value: instance.isCompleted,
                onChanged: (value) async {
                  await _dataService.updateInstanceMeta(instanceId: instance.id, isCompleted: value);
                  await _refresh();
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: template.slots.length,
                  itemBuilder: (context, index) {
                    final slot = template.slots[index];
                    final selectedPdfId = selections[slot.id];
                    final selectedPdf = selectedPdfId != null
                        ? pdfs.firstWhere(
                            (p) => p.id == selectedPdfId,
                            orElse: () => PdfFile(id: '', title: 'Desconhecido', path: ''),
                          )
                        : null;

                    final requiredTags = slot.requiredTagIds
                        .map((id) => tags.firstWhere((t) => t.id == id, orElse: () => Tag(id: id, name: id)).name)
                        .join(', ');

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text(slot.name),
                        subtitle: Text(
                          selectedPdf != null
                              ? 'Selecionado: ${selectedPdf.title}\nTags exigidas: $requiredTags'
                              : 'Nenhum arquivo selecionado\nTags exigidas: $requiredTags',
                        ),
                        isThreeLine: true,
                        trailing: selectedPdf != null
                            ? FilledButton.tonal(
                                onPressed: selectedPdf.id.isEmpty ? null : () => _openSelectedPdf(selectedPdf),
                                child: const Text('Abrir'),
                              )
                            : const Icon(Icons.arrow_forward_ios),
                        onTap: () => _selectPdfForSlot(slot.id, slot.requiredTagIds),
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
