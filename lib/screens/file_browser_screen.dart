import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/android_document_service.dart';
import '../services/data_service.dart';

class FileBrowserSelection {
  const FileBrowserSelection({required this.candidates, required this.tagIds});

  final List<PdfImportCandidate> candidates;
  final List<String> tagIds;
}

class _BreadcrumbEntry {
  const _BreadcrumbEntry({required this.uri, required this.name});

  final String uri;
  final String name;
}

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final AndroidDocumentService _documentService = const AndroidDocumentService();
  bool _loading = false;
  String? _treeUri;
  final List<_BreadcrumbEntry> _breadcrumbs = [];
  List<AndroidDocumentNode> _nodes = [];
  final Set<String> _selectedPdfUris = {};
  final Map<String, AndroidDocumentNode> _knownNodesByUri = {};
  final Map<String, String> _sourceFolderUriByPdfUri = {};
  List<String> _selectedTagIds = [];

  Future<void> _pickRootFolder() async {
    final treeUri = await _documentService.pickTree();
    if (treeUri == null) return;

    await context.read<DataService>().persistUriPermission(treeUri);
    if (!mounted) return;

    setState(() {
      _treeUri = treeUri;
      _breadcrumbs
        ..clear()
        ..add(const _BreadcrumbEntry(uri: '', name: 'Raiz'));
      _selectedPdfUris.clear();
      _knownNodesByUri.clear();
      _sourceFolderUriByPdfUri.clear();
    });

    await _loadDirectory(parentUri: treeUri, displayName: 'Raiz', replaceTrail: true);
  }

  Future<void> _loadDirectory({required String parentUri, required String displayName, bool replaceTrail = false}) async {
    if (_treeUri == null) return;

    setState(() {
      _loading = true;
    });

    try {
      final children = await _documentService.listChildren(treeUri: _treeUri!, parentUri: parentUri);
      if (!mounted) return;
      setState(() {
        _nodes = children;
        _loading = false;
        for (final node in children) {
          _knownNodesByUri[node.uri] = node;
          if (node.isPdf) {
            _sourceFolderUriByPdfUri[node.uri] = parentUri;
          }
        }
        if (replaceTrail) {
          _breadcrumbs
            ..clear()
            ..add(_BreadcrumbEntry(uri: parentUri, name: displayName));
        } else if (_breadcrumbs.isEmpty || _breadcrumbs.last.uri != parentUri) {
          _breadcrumbs.add(_BreadcrumbEntry(uri: parentUri, name: displayName));
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao listar pasta selecionada.')),
      );
    }
  }

  Future<void> _selectTags() async {
    final tags = await context.read<DataService>().getTags();
    if (!mounted) return;
    final temp = [..._selectedTagIds];

    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecionar tags', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...tags.map(
              (tag) => StatefulBuilder(
                builder: (context, setModalState) => CheckboxListTile(
                  value: temp.contains(tag.id),
                  title: Text(tag.name),
                  onChanged: (value) {
                    setModalState(() {
                      if (value == true) {
                        temp.add(tag.id);
                      } else {
                        temp.remove(tag.id);
                      }
                    });
                  },
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, temp),
                child: const Text('Aplicar tags'),
              ),
            ),
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

  List<PdfImportCandidate> _buildCandidates(Iterable<AndroidDocumentNode> nodes) {
    return nodes
        .where((n) => n.isPdf)
        .map(
          (node) => PdfImportCandidate(
            sourceId: 'saf://${node.uri}',
            displayName: node.name,
            uri: node.uri,
            sourceFolderUri:
                _sourceFolderUriByPdfUri[node.uri] ?? (_breadcrumbs.isEmpty ? _treeUri : _breadcrumbs.last.uri),
            sourceDocumentUri: node.uri,
          ),
        )
        .toList();
  }

  void _finishWithSelected() {
    final selectedNodes = _selectedPdfUris
        .map((uri) => _knownNodesByUri[uri])
        .whereType<AndroidDocumentNode>()
        .where((node) => node.isPdf);
    final candidates = _buildCandidates(selectedNodes);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione pelo menos um PDF.')));
      return;
    }
    Navigator.pop(
      context,
      FileBrowserSelection(candidates: candidates, tagIds: _selectedTagIds),
    );
  }

  Future<void> _tagCurrentFolderPdfs() async {
    final folderPdfs = _nodes.where((node) => node.isPdf).toList();
    if (folderPdfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum PDF nesta pasta.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aplicar tags na pasta atual?'),
        content: Text('Esta ação irá selecionar ${folderPdfs.length} PDF(s) da pasta aberta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _selectedPdfUris
        ..clear()
        ..addAll(folderPdfs.map((e) => e.uri));
      final sourceFolderUri = _breadcrumbs.isEmpty ? _treeUri ?? '' : _breadcrumbs.last.uri;
      for (final pdf in folderPdfs) {
        _knownNodesByUri[pdf.uri] = pdf;
        _sourceFolderUriByPdfUri[pdf.uri] = sourceFolderUri;
      }
    });

    _finishWithSelected();
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(title: const Text('Navegador de arquivos (Android)')),
      body: !isAndroid
          ? const Center(child: Text('Esta tela SAF está disponível somente no Android.'))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : _pickRootFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Escolher pasta SAF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _selectTags,
                        icon: const Icon(Icons.local_offer),
                        label: const Text('Tags'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _tagCurrentFolderPdfs,
                        icon: const Icon(Icons.playlist_add_check),
                        label: const Text('Tag em todos PDFs da pasta'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _breadcrumbs
                          .asMap()
                          .entries
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(entry.value.name),
                                onPressed: entry.value.uri.isEmpty
                                    ? null
                                    : () {
                                        _breadcrumbs.removeRange(entry.key + 1, _breadcrumbs.length);
                                        _loadDirectory(parentUri: entry.value.uri, displayName: entry.value.name, replaceTrail: true);
                                      },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _nodes.length,
                            itemBuilder: (context, index) {
                              final node = _nodes[index];
                              if (node.isDirectory) {
                                return ListTile(
                                  leading: const Icon(Icons.folder),
                                  title: Text(node.name),
                                  onTap: () => _loadDirectory(parentUri: node.uri, displayName: node.name),
                                );
                              }

                              return CheckboxListTile(
                                value: _selectedPdfUris.contains(node.uri),
                                onChanged: node.isPdf
                                    ? (value) {
                                        setState(() {
                                          if (value == true) {
                                            _knownNodesByUri[node.uri] = node;
                                            _sourceFolderUriByPdfUri[node.uri] = _breadcrumbs.isEmpty ? _treeUri ?? '' : _breadcrumbs.last.uri;
                                            _selectedPdfUris.add(node.uri);
                                          } else {
                                            _selectedPdfUris.remove(node.uri);
                                          }
                                        });
                                      }
                                    : null,
                                title: Text(node.name),
                                subtitle: Text(node.uri, maxLines: 1, overflow: TextOverflow.ellipsis),
                                secondary: Icon(node.isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file),
                              );
                            },
                          ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _finishWithSelected,
                      icon: const Icon(Icons.check),
                      label: const Text('Aplicar tags aos selecionados'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
