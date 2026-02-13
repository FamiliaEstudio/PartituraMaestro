import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:pastoral_pdf_organizer/models/pdf_file.dart';
import 'package:pastoral_pdf_organizer/models/structure_instance.dart';
import 'package:pastoral_pdf_organizer/models/structure_template.dart';
import 'package:pastoral_pdf_organizer/models/tag.dart';
import 'package:pastoral_pdf_organizer/services/data_service.dart';
import 'package:pastoral_pdf_organizer/services/uri_access_service.dart';

import 'test_db_utils.dart';

class _FakeUriAccessService extends UriAccessService {
  _FakeUriAccessService({
    this.treeDocs = const <UriDocumentMetadata>[],
    this.bytesByUri = const <String, Uint8List>{},
    this.persistResult = true,
  });

  final List<UriDocumentMetadata> treeDocs;
  final Map<String, Uint8List> bytesByUri;
  final bool persistResult;

  @override
  Future<List<UriDocumentMetadata>> listTreeDocumentsRecursively(
          String treeUri) async =>
      treeDocs;

  @override
  Future<Uint8List?> readBytes(String uri) async => bytesByUri[uri];

  @override
  Future<bool> persistReadPermission(String uri) async => persistResult;
}

void main() {
  final service = DataService();

  setUpAll(configureTestDatabase);

  setUp(() async {
    await resetDatabase();
  });

  test('filtra PDFs exigindo todas as tags do slot', () async {
    await service.addTag(Tag(id: 'tag-entrada', name: 'Entrada'));
    await service.addTag(Tag(id: 'tag-natal', name: 'Natal'));
    await service.addTag(Tag(id: 'tag-gloria', name: 'Glória'));

    await service.addPdf(
      PdfFile(
        id: 'pdf-1',
        path: '/tmp/entrada-natal.pdf',
        title: 'Entrada Natal',
        tagIds: ['tag-entrada', 'tag-natal'],
      ),
    );
    await service.addPdf(
      PdfFile(
        id: 'pdf-2',
        path: '/tmp/entrada.pdf',
        title: 'Entrada Comum',
        tagIds: ['tag-entrada'],
      ),
    );

    final onlyEntrada = await service.findPdfsByTags(['tag-entrada']);
    final entradaNatal =
        await service.findPdfsByTags(['tag-entrada', 'tag-natal']);
    final semResultado =
        await service.findPdfsByTags(['tag-gloria', 'tag-natal']);

    expect(onlyEntrada.map((e) => e.id), containsAll(['pdf-1', 'pdf-2']));
    expect(entradaNatal.map((e) => e.id), ['pdf-1']);
    expect(semResultado, isEmpty);
  });

  test('persistência de seleção por slot mantém vínculo com instância',
      () async {
    await service.addTag(Tag(id: 'tag-entrada', name: 'Entrada'));
    final template = StructureTemplate(
      id: 'tpl-1',
      name: 'Missa',
      slots: [
        SubStructureSlot(
            id: 'slot-entrada',
            name: 'Entrada',
            requiredTagIds: ['tag-entrada']),
      ],
    );
    await service.addTemplate(template);

    await service.addPdf(
      PdfFile(
        id: 'pdf-entrada',
        path: '/tmp/entrada.pdf',
        title: 'Entrada',
        tagIds: ['tag-entrada'],
      ),
    );

    await service.addInstance(
      StructureInstance(
        id: 'inst-1',
        templateId: template.id,
        name: 'Missa 2026-01-01',
        createdAt: DateTime(2026, 1, 1),
        templateSnapshot: template,
      ),
    );

    await service.updateInstanceSelection(
        'inst-1', 'slot-entrada', ['pdf-entrada']);

    final selections = await service.getInstanceSelections('inst-1');
    expect(selections['slot-entrada'], ['pdf-entrada']);

    await service.clearInstanceSelection('inst-1', 'slot-entrada');
    final cleared = await service.getInstanceSelections('inst-1');
    expect(cleared.containsKey('slot-entrada'), isFalse);
  });

  test('bloqueia importação duplicada por caminho e por hash', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdf-dup');
    final originalPath = p.join(tempDir.path, 'original.pdf');
    final duplicatePath = p.join(tempDir.path, 'duplicate.pdf');
    final pdfBytes =
        '%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF'.codeUnits;

    await File(originalPath).writeAsBytes(pdfBytes);
    await File(duplicatePath).writeAsBytes(pdfBytes);

    final initial = await service.importPdfCandidates(
      candidates: [
        PdfImportCandidate(sourceId: originalPath, displayName: 'original.pdf'),
      ],
      tagIds: const [],
      idPrefix: 'dup-check',
    );

    expect(initial.importedCount, 1);
    expect(initial.updatedCount, 0);
    expect(initial.errors, isEmpty);

    final duplicateResult = await service.importPdfCandidates(
      candidates: [
        PdfImportCandidate(sourceId: originalPath, displayName: 'original.pdf'),
        PdfImportCandidate(
            sourceId: duplicatePath, displayName: 'duplicate.pdf'),
      ],
      tagIds: const [],
      idPrefix: 'dup-check',
    );

    expect(duplicateResult.importedCount, 0);
    expect(duplicateResult.updatedCount, 0);
    expect(
      duplicateResult.errors.map((e) => e.reason),
      containsAll([
        '[DUPLICATE_PATH] Arquivo já importado (mesmo caminho).',
        '[DUPLICATE_HASH] Arquivo duplicado detectado por hash.',
      ]),
    );

    await tempDir.delete(recursive: true);
  });

  test('mergeTags atualiza tags em PDF já importado por caminho', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdf-upsert-tags');
    final originalPath = p.join(tempDir.path, 'original.pdf');
    final pdfBytes =
        '%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF'.codeUnits;

    await File(originalPath).writeAsBytes(pdfBytes);
    await service.addTag(Tag(id: 'tag-a', name: 'Tag A'));
    await service.addTag(Tag(id: 'tag-b', name: 'Tag B'));

    final initial = await service.importPdfCandidates(
      candidates: [
        PdfImportCandidate(sourceId: originalPath, displayName: 'original.pdf'),
      ],
      tagIds: const ['tag-a'],
      idPrefix: 'upsert-check',
    );

    final merged = await service.importPdfCandidates(
      candidates: [
        PdfImportCandidate(sourceId: originalPath, displayName: 'original.pdf'),
      ],
      tagIds: const ['tag-b'],
      idPrefix: 'upsert-check',
      onDuplicate: DuplicateImportBehavior.mergeTags,
    );

    expect(initial.importedCount, 1);
    expect(initial.updatedCount, 0);
    expect(merged.importedCount, 0);
    expect(merged.updatedCount, 1);
    expect(merged.errors, isEmpty);

    final pdfs = await service.getPdfs();
    expect(pdfs, hasLength(1));
    expect(pdfs.single.tagIds.toSet(), {'tag-a', 'tag-b'});

    await tempDir.delete(recursive: true);
  });

  test('relocalização atualiza caminho quando arquivo foi movido', () async {
    await service.addPdf(
      PdfFile(
        id: 'pdf-reloc',
        path: '/tmp/nao-existe.pdf',
        title: 'Arquivo movido',
        tagIds: const [],
      ),
    );

    await service.updatePdfLocation('pdf-reloc', '/tmp/relocalizado.pdf');

    final updated = (await service.getPdfs()).single;
    expect(updated.path, '/tmp/relocalizado.pdf');
    expect(updated.uri, isNull);
  });

  test('exclusão/substituição de tag atualiza vínculos em PDFs e slots',
      () async {
    await service.addTag(Tag(id: 'tag-antiga', name: 'Antiga'));
    await service.addTag(Tag(id: 'tag-nova', name: 'Nova'));

    await service.addPdf(
      PdfFile(
        id: 'pdf-1',
        path: '/tmp/hino.pdf',
        title: 'Hino',
        tagIds: ['tag-antiga'],
      ),
    );

    await service.addTemplate(
      StructureTemplate(
        id: 'tpl-1',
        name: 'Missa',
        slots: [
          SubStructureSlot(
              id: 'slot-1', name: 'Entrada', requiredTagIds: ['tag-antiga']),
        ],
      ),
    );

    await service.deleteTagWithStrategy(
        tagId: 'tag-antiga', replacementTagId: 'tag-nova');

    final pdfAfterReplace = (await service.getPdfs()).single;
    expect(pdfAfterReplace.tagIds, ['tag-nova']);

    final templateAfterReplace = (await service.getTemplates()).single;
    expect(templateAfterReplace.slots.single.requiredTagIds, ['tag-nova']);

    await service.deleteTag('tag-nova');

    final pdfAfterDelete = (await service.getPdfs()).single;
    expect(pdfAfterDelete.tagIds, isEmpty);

    final templateAfterDelete = (await service.getTemplates()).single;
    expect(templateAfterDelete.slots.single.requiredTagIds, isEmpty);
  });

  test('importa candidato SAF e persiste metadados de origem', () async {
    const uri = 'content://com.example/tree/root/document.pdf';

    final result = await service.importPdfCandidates(
      candidates: const [
        PdfImportCandidate(
          sourceId: 'saf://content://com.example/tree/root/document.pdf',
          displayName: 'document.pdf',
          uri: uri,
          sourceFolderUri: 'content://com.example/tree/root',
          sourceDocumentUri: uri,
        ),
      ],
      tagIds: const [],
      idPrefix: 'saf',
      generateHash: false,
    );

    expect(result.importedCount, 1);
    expect(result.updatedCount, 0);

    final imported = (await service.getPdfs()).single;
    expect(imported.uri, uri);
    expect(imported.sourceFolderUri, 'content://com.example/tree/root');
    expect(imported.sourceDocumentUri, uri);
  });

  test('scanPdfDirectory retorna candidatos PDF via URI SAF', () async {
    final serviceWithUriScan = DataService(
      uriAccessService: _FakeUriAccessService(
        treeDocs: const [
          UriDocumentMetadata(
            displayName: 'Hino.pdf',
            uri: 'content://tree/root/hino',
            size: 100,
            mimeType: 'application/pdf',
          ),
          UriDocumentMetadata(
            displayName: 'nota.txt',
            uri: 'content://tree/root/nota',
            size: 30,
            mimeType: 'text/plain',
          ),
        ],
      ),
    );

    final scanned =
        await serviceWithUriScan.scanPdfDirectory('content://tree/root');

    expect(scanned, hasLength(1));
    expect(scanned.single.displayName, 'Hino.pdf');
    expect(scanned.single.uri, 'content://tree/root/hino');
    expect(scanned.single.path, 'saf://content://tree/root/hino');
  });

  test('bloqueia template duplicado ignorando caixa e acento', () async {
    await service.addTemplate(
      StructureTemplate(
        id: 'tpl-1',
        name: 'Míssa Solene',
        slots: [
          SubStructureSlot(id: 'slot-1', name: 'Entrada'),
        ],
      ),
    );

    expect(
      () => service.addTemplate(
        StructureTemplate(
          id: 'tpl-2',
          name: 'missa solene',
          slots: [
            SubStructureSlot(id: 'slot-2', name: 'Ofertório'),
          ],
        ),
      ),
      throwsA(isA<TemplateNameConflictException>()),
    );
  });

  test('bloqueia template com slot sem nome válido', () async {
    expect(
      () => service.addTemplate(
        StructureTemplate(
          id: 'tpl-invalid-slot',
          name: 'Missa',
          slots: [
            SubStructureSlot(id: 'slot-empty', name: '   '),
          ],
        ),
      ),
      throwsA(isA<SlotNameValidationException>()),
    );
  });

  test(
      'bloqueia template com nomes de slot duplicados ignorando caixa e acento',
      () async {
    expect(
      () => service.addTemplate(
        StructureTemplate(
          id: 'tpl-dup-slot',
          name: 'Missa de testes',
          slots: [
            SubStructureSlot(id: 'slot-1', name: 'Glória'),
            SubStructureSlot(id: 'slot-2', name: 'gloria'),
          ],
        ),
      ),
      throwsA(isA<SlotNameValidationException>()),
    );
  });

  test('importPdfCandidates lê bytes de candidato URI sem filesystem local',
      () async {
    const uri = 'content://tree/root/documento';
    final pdfBytes = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
    final serviceWithUriRead = DataService(
      uriAccessService:
          _FakeUriAccessService(bytesByUri: {uri: pdfBytes}, persistResult: false),
    );

    final result = await serviceWithUriRead.importPdfCandidates(
      candidates: const [
        PdfImportCandidate(
          sourceId: 'saf://content://tree/root/documento',
          displayName: 'documento.pdf',
          uri: uri,
          sourceFolderUri: 'content://tree/root',
          sourceDocumentUri: uri,
        ),
      ],
      tagIds: const [],
      idPrefix: 'uri-only',
      generateHash: true,
    );

    expect(result.importedCount, 1);
    expect(result.updatedCount, 0);
    expect(result.errors, isEmpty);
    final imported = (await serviceWithUriRead.getPdfs()).single;
    expect(imported.path, 'saf://content://tree/root/documento');
    expect(imported.fileHash, isNotNull);
  });
}
