import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../models/pdf_file.dart';
import '../models/tag.dart';
import '../services/data_service.dart';

class PdfLibraryScreen extends StatefulWidget {
  const PdfLibraryScreen({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<PdfLibraryScreen> createState() => _PdfLibraryScreenState();
}

class _PdfLibraryScreenState extends State<PdfLibraryScreen> {
  final DataService _dataService = DataService();

  Future<void> _addPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final fileName = path.basenameWithoutExtension(filePath);
    final selectedTagIds = await _openTagSelector();
    if (selectedTagIds == null) return;

    _dataService.addPdf(
      PdfFile(
        id: const Uuid().v4(),
        path: filePath,
        title: fileName,
        tagIds: selectedTagIds,
      ),
    );

    setState(() {});
    widget.onDataChanged();
  }

  Future<List<String>?> _openTagSelector({List<String>? initialTagIds}) {
    final allTags = _dataService.getTags();
    final selected = [...?initialTagIds];

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione as tags do PDF',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (allTags.isEmpty)
              const Text('Crie tags na aba "Tags" antes de classificar PDFs.'),
            ...allTags.map(
              (tag) => StatefulBuilder(
                builder: (context, setModalState) => CheckboxListTile(
                  value: selected.contains(tag.id),
                  title: Text(tag.name),
                  onChanged: (value) {
                    setModalState(() {
                      if (value == true) {
                        selected.add(tag.id);
                      } else {
                        selected.remove(tag.id);
                      }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPdfTags(PdfFile pdf) async {
    final updated = await _openTagSelector(initialTagIds: pdf.tagIds);
    if (updated == null) return;

    setState(() {
      pdf.tagIds = updated;
    });

    widget.onDataChanged();
  }

  String _tagNames(List<String> ids, List<Tag> allTags) {
    if (ids.isEmpty) return 'Sem tags';
    final names = ids
        .map((id) => allTags.firstWhere((tag) => tag.id == id, orElse: () => Tag(id: id, name: id)).name)
        .toList();
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final pdfs = _dataService.getPdfs();
    final tags = _dataService.getTags();

    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca de PDFs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPdf,
        icon: const Icon(Icons.upload_file),
        label: const Text('Adicionar PDF'),
      ),
      body: pdfs.isEmpty
          ? const Center(
              child: Text('Nenhum PDF cadastrado.'),
            )
          : ListView.builder(
              itemCount: pdfs.length,
              itemBuilder: (context, index) {
                final pdf = pdfs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(pdf.title),
                    subtitle: Text(
                      '${_tagNames(pdf.tagIds, tags)}\n${pdf.path}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      onPressed: () => _editPdfTags(pdf),
                      icon: const Icon(Icons.edit),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
