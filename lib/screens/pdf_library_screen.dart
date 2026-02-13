import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/usecases/assign_pdf_tags.dart';
import '../models/pdf_file.dart';
import '../models/tag.dart';
import '../services/data_service.dart';
import 'file_browser_screen.dart';
import 'import_pdf_screen.dart';
import 'pdf_viewer_screen.dart';

class PdfLibraryScreen extends StatefulWidget {
  const PdfLibraryScreen({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<PdfLibraryScreen> createState() => _PdfLibraryScreenState();
}

class _PdfLibraryScreenState extends State<PdfLibraryScreen> {
    late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final pdfs = await context.read<DataService>().getPdfs();
    final tags = await context.read<DataService>().getTags();
    return {'pdfs': pdfs, 'tags': tags};
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadData();
    });
    widget.onDataChanged();
  }

  Future<void> _openImportScreen() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Importação tradicional'),
              onTap: () => Navigator.pop(context, 'classic'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Navegador Android-first (SAF)'),
              onTap: () => Navigator.pop(context, 'saf'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'classic') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImportPdfScreen(onImported: _reload),
        ),
      );
      await _reload();
      return;
    }

    final selection = await Navigator.push<FileBrowserSelection>(
      context,
      MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
    );
    if (selection == null) return;

    final result = await context.read<DataService>().importPdfCandidates(
      candidates: selection.candidates,
      tagIds: selection.tagIds,
      idPrefix: DateTime.now().millisecondsSinceEpoch.toString(),
      generateHash: true,
      onDuplicate: DuplicateImportBehavior.mergeTags,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.importedCount} importado(s), ${result.updatedCount} atualizado(s), ${result.errors.length} erro(s).')),
    );
    await _reload();
  }

  Future<void> _openPdf(PdfFile pdf) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfFile: pdf)),
    );
    await _reload();
  }

  Future<List<String>?> _openTagSelector({List<String>? initialTagIds}) async {
    final allTags = await context.read<DataService>().getTags();
    final selected = [...?initialTagIds];

    if (!mounted) return null;

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
            if (allTags.isEmpty) const Text('Crie tags na aba "Tags" antes de classificar PDFs.'),
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

    await context.read<AssignPdfTags>()(pdfId: pdf.id, tagIds: updated);
    await _reload();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca de PDFs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openImportScreen,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importar PDFs'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final pdfs = (snapshot.data?['pdfs'] as List<PdfFile>?) ?? [];
          final tags = (snapshot.data?['tags'] as List<Tag>?) ?? [];

          if (pdfs.isEmpty) {
            return const Center(
              child: Text('Nenhum PDF cadastrado.'),
            );
          }

          return ListView.builder(
            itemCount: pdfs.length,
            itemBuilder: (context, index) {
              final pdf = pdfs[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(pdf.displayName),
                  subtitle: Text(
                    '${_tagNames(pdf.tagIds, tags)}\n${pdf.path}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _openPdf(pdf),
                        child: const Text('Abrir'),
                      ),
                      IconButton(
                        onPressed: () => _editPdfTags(pdf),
                        icon: const Icon(Icons.edit),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
