import 'package:flutter/material.dart';

import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../services/data_service.dart';

class InstanceSelectionScreen extends StatefulWidget {
  const InstanceSelectionScreen({super.key, required this.instance});

  final StructureInstance instance;

  @override
  State<InstanceSelectionScreen> createState() => _InstanceSelectionScreenState();
}

class _InstanceSelectionScreenState extends State<InstanceSelectionScreen> {
  late StructureTemplate _template;
  final DataService _dataService = DataService();

  @override
  void initState() {
    super.initState();
    _template = _dataService.getTemplate(widget.instance.templateId)!;
  }

  void _selectPdfForSlot(String slotId, List<String> requiredTags) {
    final candidates = _dataService.findPdfsByTags(requiredTags);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        if (candidates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nenhum PDF corresponde às tags exigidas para esta sub-estrutura.',
            ),
          );
        }

        return ListView.builder(
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final pdf = candidates[index];
            return ListTile(
              title: Text(pdf.title),
              onTap: () {
                setState(() {
                  _dataService.updateInstanceSelection(widget.instance.id, slotId, pdf.id);
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.instance.name)),
      body: ListView.builder(
        itemCount: _template.slots.length,
        itemBuilder: (context, index) {
          final slot = _template.slots[index];
          final selectedPdfId = widget.instance.selectedPdfIds[slot.id];
          final selectedPdf = selectedPdfId != null
              ? _dataService.getPdfs().firstWhere(
                    (p) => p.id == selectedPdfId,
                    orElse: () => PdfFile(
                      id: '',
                      title: 'Desconhecido',
                      path: '',
                    ),
                  )
              : null;

          final requiredTags = slot.requiredTagIds
              .map((id) => _dataService.getTag(id)?.name ?? id)
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
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _selectPdfForSlot(slot.id, slot.requiredTagIds),
            ),
          );
        },
      ),
    );
  }
}
