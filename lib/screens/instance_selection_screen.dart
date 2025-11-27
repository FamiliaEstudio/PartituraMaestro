import 'package:flutter/material.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/pdf_file.dart';
import '../services/data_service.dart';

class InstanceSelectionScreen extends StatefulWidget {
  final StructureInstance instance;

  InstanceSelectionScreen({required this.instance});

  @override
  _InstanceSelectionScreenState createState() => _InstanceSelectionScreenState();
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
    // Busca PDFs que correspondem às tags do slot
    final candidates = _dataService.findPdfsByTags(requiredTags);

    showModalBottomSheet(
      context: context,
      builder: (context) {
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
              ? _dataService.getPdfs().firstWhere((p) => p.id == selectedPdfId, orElse: () => PdfFile(id: '', title: 'Desconhecido', path: ''))
              : null;

          return Card(
            margin: const EdgeInsets.all(8.0),
            child: ListTile(
              title: Text(slot.name),
              subtitle: Text(selectedPdf != null ? 'Selecionado: ${selectedPdf.title}' : 'Nenhum arquivo selecionado'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _selectPdfForSlot(slot.id, slot.requiredTagIds),
            ),
          );
        },
      ),
    );
  }
}
