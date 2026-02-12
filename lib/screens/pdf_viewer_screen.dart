import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/pdf_file.dart';
import '../services/data_service.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.pdfFile});

  final PdfFile pdfFile;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final DataService _dataService = DataService();
  late PdfFile _pdf;
  late Future<String> _preparedPathFuture;

  @override
  void initState() {
    super.initState();
    _pdf = widget.pdfFile;
    _preparedPathFuture = _preparePdfPath();
  }

  Future<String> _preparePdfPath() async {
    final source = File(_pdf.path);
    if (!await source.exists()) {
      throw const _PdfSourceMissingException();
    }

    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'pdf_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final fileLength = await source.length();
    const largeFileThreshold = 15 * 1024 * 1024;
    if (fileLength < largeFileThreshold) {
      return source.path;
    }

    final pathHash = md5.convert(_pdf.path.codeUnits).toString();
    final extension = p.extension(_pdf.path).isEmpty ? '.pdf' : p.extension(_pdf.path);
    final cachedFile = File(p.join(cacheDir.path, '$pathHash$extension'));

    if (await cachedFile.exists()) {
      final sourceModified = await source.lastModified();
      final cacheModified = await cachedFile.lastModified();
      if (!sourceModified.isAfter(cacheModified) && await cachedFile.length() == fileLength) {
        return cachedFile.path;
      }
    }

    await source.copy(cachedFile.path);
    return cachedFile.path;
  }

  Future<void> _relocalizeFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );

    final selectedPath = result?.files.single.path;
    if (selectedPath == null) {
      return;
    }

    final selectedFile = File(selectedPath);
    if (!await selectedFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arquivo selecionado não está acessível.')),
      );
      return;
    }

    await _dataService.updatePdfLocation(
      _pdf.id,
      selectedPath,
      uri: null,
    );

    setState(() {
      _pdf = PdfFile(
        id: _pdf.id,
        path: selectedPath,
        title: _pdf.title,
        uri: null,
        displayName: _pdf.displayName,
        fileHash: _pdf.fileHash,
        tagIds: _pdf.tagIds,
      );
      _preparedPathFuture = _preparePdfPath();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pdf.displayName),
      ),
      body: FutureBuilder<String>(
        future: _preparedPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            final missing = snapshot.error is _PdfSourceMissingException;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    missing ? Icons.folder_off : Icons.error_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    missing
                        ? 'Arquivo ausente ou movido. Relocalize para continuar.'
                        : 'Falha ao abrir o arquivo PDF.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (missing)
                    FilledButton.icon(
                      onPressed: _relocalizeFile,
                      icon: const Icon(Icons.find_in_page_outlined),
                      label: const Text('Relocalizar arquivo'),
                    ),
                ],
              ),
            );
          }

          final resolvedPath = snapshot.data!;
          return SfPdfViewer.file(
            File(resolvedPath),
            canShowPaginationDialog: true,
            pageLayoutMode: PdfPageLayoutMode.continuous,
          );
        },
      ),
    );
  }
}

class _PdfSourceMissingException implements Exception {
  const _PdfSourceMissingException();
}
