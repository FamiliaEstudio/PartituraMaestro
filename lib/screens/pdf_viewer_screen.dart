import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/pdf_file.dart';
import '../services/data_service.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.pdfFile,
    this.prefetchedPdfFile,
  });

  final PdfFile pdfFile;
  final PdfFile? prefetchedPdfFile;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfFile _pdf;
  late Future<_PreparedPdfSource> _preparedSourceFuture;

  @override
  void initState() {
    super.initState();
    _pdf = widget.pdfFile;
    _preparedSourceFuture = _preparePdfSource(_pdf);

    final nextPdf = widget.prefetchedPdfFile;
    if (nextPdf != null) {
      _warmUpPdfSource(nextPdf);
    }
  }

  Future<_PreparedPdfSource> _preparePdfSource(PdfFile pdf) async {
    return _PdfSourceLoader.preparePdfSource(
      pdf: pdf,
      dataService: context.read<DataService>(),
    );
  }

  void _warmUpPdfSource(PdfFile pdf) {
    _PdfSourceLoader.preparePdfSource(
      pdf: pdf,
      dataService: context.read<DataService>(),
    ).catchError((_) {
      // Pré-carregamento é melhor esforço e não deve interromper a experiência.
    });
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

    await context.read<DataService>().updatePdfLocation(
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
      _preparedSourceFuture = _preparePdfSource(_pdf);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pdf.displayName),
      ),
      body: FutureBuilder<_PreparedPdfSource>(
        future: _preparedSourceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            final missing = snapshot.error is _PdfSourceMissingException;
            final uriMissing = snapshot.error is _PdfUriAccessException;
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
                        : uriMissing
                            ? 'Não foi possível acessar a URI do documento. Relocalize para continuar.'
                            : 'Falha ao abrir o arquivo PDF.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (missing || uriMissing)
                    FilledButton.icon(
                      onPressed: _relocalizeFile,
                      icon: const Icon(Icons.find_in_page_outlined),
                      label: const Text('Relocalizar arquivo'),
                    ),
                ],
              ),
            );
          }

          final prepared = snapshot.data!;
          if (prepared.path != null) {
            return SfPdfViewer.file(
              File(prepared.path!),
              canShowPaginationDialog: true,
              pageLayoutMode: PdfPageLayoutMode.continuous,
            );
          }

          return SfPdfViewer.memory(
            prepared.bytes!,
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

class _PdfUriAccessException implements Exception {
  const _PdfUriAccessException();
}

class _PreparedPdfSource {
  const _PreparedPdfSource._({this.path, this.bytes});

  final String? path;
  final Uint8List? bytes;

  factory _PreparedPdfSource.path(String path) {
    return _PreparedPdfSource._(path: path);
  }

  factory _PreparedPdfSource.bytes(Uint8List bytes) {
    return _PreparedPdfSource._(bytes: bytes);
  }
}

class _PdfSourceLoader {
  static Future<_PreparedPdfSource> preparePdfSource({
    required PdfFile pdf,
    required DataService dataService,
  }) async {
    final source = File(pdf.path);
    if (await source.exists()) {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(appDir.path, 'pdf_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final fileLength = await source.length();
      const largeFileThreshold = 15 * 1024 * 1024;
      if (fileLength < largeFileThreshold) {
        return _PreparedPdfSource.path(source.path);
      }

      final pathHash = md5.convert(pdf.path.codeUnits).toString();
      final extension = p.extension(pdf.path).isEmpty ? '.pdf' : p.extension(pdf.path);
      final cachedFile = File(p.join(cacheDir.path, '$pathHash$extension'));

      if (await cachedFile.exists()) {
        final sourceModified = await source.lastModified();
        final cacheModified = await cachedFile.lastModified();
        if (!sourceModified.isAfter(cacheModified) && await cachedFile.length() == fileLength) {
          return _PreparedPdfSource.path(cachedFile.path);
        }
      }

      await source.copy(cachedFile.path);
      return _PreparedPdfSource.path(cachedFile.path);
    }

    final uri = pdf.uri;
    if (uri != null && uri.startsWith('content://')) {
      final bytes = await dataService.readUriBytes(uri);
      if (bytes != null && bytes.isNotEmpty) {
        return _PreparedPdfSource.bytes(bytes);
      }
      throw const _PdfUriAccessException();
    }

    throw const _PdfSourceMissingException();
  }
}
