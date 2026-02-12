import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/usecases/find_candidate_pdfs.dart';
import '../models/tag.dart';
import '../services/data_service.dart';
import 'file_browser_screen.dart';

enum ImportMode { files, folder }

class ImportPdfScreen extends StatefulWidget {
  const ImportPdfScreen({super.key, required this.onImported});

  final VoidCallback onImported;

  @override
  State<ImportPdfScreen> createState() => _ImportPdfScreenState();
}

class _ImportPdfScreenState extends State<ImportPdfScreen> {
  
  ImportMode _mode = ImportMode.files;
  bool _loading = false;
  bool _generateHash = true;
  List<PdfImportCandidate> _candidates = [];
  Set<String> _selectedPaths = {};
  List<String> _selectedTagIds = [];
  List<ImportError> _errors = [];

  Future<void> _pickFiles() async {
    final hasPermission = await context.read<DataService>().ensureAndroidStoragePermission();
    if (!hasPermission) {
      _showMsg('Permissão de armazenamento negada.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return;

    final selected = result.files
        .where((f) => f.path != null)
        .map(
          (f) => PdfImportCandidate(
            path: f.path!,
            displayName: f.name,
            uri: f.identifier,
          ),
        )
        .toList();

    setState(() {
      _candidates = selected;
      _selectedPaths = selected.map((e) => e.path).toSet();
      _errors = [];
    });
  }

  Future<void> _pickWithAndroidBrowser() async {
    final selection = await Navigator.push<FileBrowserSelection>(
      context,
      MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
    );
    if (selection == null) return;

    setState(() {
      _candidates = selection.candidates;
      _selectedPaths = selection.candidates.map((e) => e.path).toSet();
      _selectedTagIds = selection.tagIds;
      _errors = [];
    });
  }

  Future<void> _pickFolderAndScan() async {
    final hasPermission = await context.read<DataService>().ensureAndroidStoragePermission();
    if (!hasPermission) {
      _showMsg('Permissão de armazenamento negada.');
      return;
    }

    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;

    setState(() {
      _loading = true;
      _errors = [];
    });

    try {
      final scanned = await context.read<FindCandidatePdfs>()(directory);
      setState(() {
        _candidates = scanned;
        _selectedPaths = scanned.map((e) => e.path).toSet();
      });
    } catch (e) {
      _showMsg('Falha ao varrer pasta: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _selectTags() async {
    final allTags = await context.read<DataService>().getTags();
    if (!mounted) return;

    final temp = [..._selectedTagIds];
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aplicar tags em lote', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (allTags.isEmpty) const Text('Nenhuma tag cadastrada.'),
            ...allTags.map((tag) {
              return StatefulBuilder(
                builder: (context, setModalState) => CheckboxListTile(
                  value: temp.contains(tag.id),
                  title: Text(tag.name),
                  onChanged: (v) {
                    setModalState(() {
                      if (v == true) {
                        temp.add(tag.id);
                      } else {
                        temp.remove(tag.id);
                      }
                    });
                  },
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, temp),
                child: const Text('Aplicar'),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedTagIds = selected;
      });
    }
  }

  Future<void> _importSelected() async {
    final selected = _candidates.where((c) => _selectedPaths.contains(c.path)).toList();
    if (selected.isEmpty) {
      _showMsg('Selecione ao menos um arquivo PDF.');
      return;
    }

    setState(() {
      _loading = true;
      _errors = [];
    });

    final result = await context.read<DataService>().importPdfCandidates(
      candidates: selected,
      tagIds: _selectedTagIds,
      idPrefix: const Uuid().v4(),
      generateHash: _generateHash,
    );

    setState(() {
      _errors = result.errors;
      _loading = false;
    });

    if (!mounted) return;

    widget.onImported();
    _showMsg('${result.importedCount} arquivo(s) importado(s). ${result.errors.length} erro(s).');

    if (result.importedCount > 0) {
      Navigator.pop(context);
    }
  }

  void _showMsg(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _tagSummary(List<Tag> tags) {
    if (_selectedTagIds.isEmpty) return 'Sem tags em lote';
    final names = tags.where((t) => _selectedTagIds.contains(t.id)).map((e) => e.name).toList();
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Tag>>(
      future: context.read<DataService>().getTags(),
      builder: (context, tagSnapshot) {
        final tags = tagSnapshot.data ?? [];

        return Scaffold(
          appBar: AppBar(title: const Text('Importar PDFs')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<ImportMode>(
                  segments: const [
                    ButtonSegment(value: ImportMode.files, label: Text('Selecionar arquivos'), icon: Icon(Icons.upload_file)),
                    ButtonSegment(value: ImportMode.folder, label: Text('Selecionar pasta'), icon: Icon(Icons.folder_open)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) {
                    setState(() {
                      _mode = value.first;
                      _candidates = [];
                      _selectedPaths = {};
                      _errors = [];
                    });
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () async {
                              if (_mode == ImportMode.files) {
                                await _pickFiles();
                              } else {
                                await _pickFolderAndScan();
                              }
                            },
                      icon: Icon(_mode == ImportMode.files ? Icons.upload_file : Icons.folder),
                      label: Text(_mode == ImportMode.files ? 'Selecionar PDFs' : 'Selecionar pasta e varrer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _selectTags,
                      icon: const Icon(Icons.local_offer),
                      label: const Text('Tags em lote'),
                    ),
                    if (Platform.isAndroid)
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _pickWithAndroidBrowser,
                        icon: const Icon(Icons.phone_android),
                        label: const Text('Navegador Android (SAF)'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Tags atuais: ${_tagSummary(tags)}'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _generateHash,
                  onChanged: _loading
                      ? null
                      : (v) {
                          setState(() {
                            _generateHash = v ?? true;
                          });
                        },
                  title: const Text('Gerar hash para deduplicação'),
                ),
                const Divider(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _candidates.isEmpty
                          ? const Center(child: Text('Nenhum arquivo pronto para importação.'))
                          : ListView.builder(
                              itemCount: _candidates.length,
                              itemBuilder: (context, index) {
                                final item = _candidates[index];
                                final checked = _selectedPaths.contains(item.path);
                                final isPdf = item.path.toLowerCase().endsWith('.pdf') ||
                                    item.displayName.toLowerCase().endsWith('.pdf');
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: isPdf
                                      ? (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedPaths.add(item.path);
                                            } else {
                                              _selectedPaths.remove(item.path);
                                            }
                                          });
                                        }
                                      : null,
                                  title: Text(item.displayName),
                                  subtitle: Text(item.path),
                                  secondary: Icon(isPdf ? Icons.picture_as_pdf : Icons.error_outline),
                                );
                              },
                            ),
                ),
                if (_errors.isNotEmpty) ...[
                  const Divider(),
                  const Text('Erros por arquivo', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      itemCount: _errors.length,
                      itemBuilder: (context, i) {
                        final err = _errors[i];
                        return Text('• ${err.source}: ${err.reason}');
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _importSelected,
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar na biblioteca'),
                  ),
                ),
                if (Platform.isAndroid)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Android: permissões de armazenamento serão solicitadas. Quando o acesso URI não puder ser mantido, será necessário relocalizar o PDF depois.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
