import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dtos/pdf_file_dto.dart';
import '../data/dtos/tag_dto.dart';
import '../data/mappers/pdf_file_mapper.dart';
import '../data/mappers/tag_mapper.dart';
import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import 'storage/database_service.dart';
import 'uri_access_service.dart';

class ImportError {
  final String code;
  final String source;
  final String cause;

  String get reason => '[$code] $cause';

  const ImportError({required this.code, required this.source, required this.cause});
}

class ImportResult {
  final int importedCount;
  final int updatedCount;
  final List<ImportError> errors;

  const ImportResult({required this.importedCount, required this.updatedCount, required this.errors});
}

enum DuplicateImportBehavior { skip, mergeTags }

class PdfImportCandidate {
  final String sourceId;
  final String displayName;
  final String? uri;
  final String? sourceFolderUri;
  final String? sourceDocumentUri;
  final int? size;
  final String? mimeType;

  const PdfImportCandidate({
    required this.sourceId,
    required this.displayName,
    this.uri,
    this.sourceFolderUri,
    this.sourceDocumentUri,
    this.size,
    this.mimeType,
  });

  String get path => sourceId;

  bool get isUriSource => uri != null && uri!.startsWith('content://');
}

class TagUsageStats {
  final int pdfCount;
  final int slotCount;

  const TagUsageStats({required this.pdfCount, required this.slotCount});
}

class TagNameConflictException implements Exception {
  final String message;

  const TagNameConflictException(this.message);

  @override
  String toString() => message;
}

class TemplateNameConflictException implements Exception {
  final String message;

  const TemplateNameConflictException(this.message);

  @override
  String toString() => message;
}

class SlotNameValidationException implements Exception {
  final String message;

  const SlotNameValidationException(this.message);

  @override
  String toString() => message;
}

class DataService {
  DataService({DatabaseService? databaseService, UriAccessService? uriAccessService})
      : _databaseService = databaseService ?? DatabaseService(),
        _uriAccessService = uriAccessService ?? const UriAccessService();

  final DatabaseService _databaseService;
  final UriAccessService _uriAccessService;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _databaseService.database;
    _initialized = true;

    final tags = await getTags();
    final pdfs = await getPdfs();
    if (tags.isEmpty && pdfs.isEmpty) {
      await _seedInitialData();
    }
  }

  Future<Database> get _db async => _databaseService.database;

  Future<void> _seedInitialData() async {
    await addTag(Tag(id: 't1', name: 'Entrada'));
    await addTag(Tag(id: 't2', name: 'Natal'));
    await addTag(Tag(id: 't3', name: 'Glória'));

    await addPdf(
      PdfFile(
        id: 'p1',
        path: '/docs/canto1.pdf',
        title: 'Canto de Entrada Natal',
        displayName: 'Canto de Entrada Natal',
        tagIds: ['t1', 't2'],
      ),
    );
    await addPdf(
      PdfFile(
        id: 'p2',
        path: '/docs/canto2.pdf',
        title: 'Glória Solene',
        displayName: 'Glória Solene',
        tagIds: ['t3'],
      ),
    );
  }

  Future<void> addTag(Tag tag) async {
    await _assertTagNameAvailable(tag.name);
    final db = await _db;
    await db.insert(
      'tags',
      TagMapper.toDto(tag).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateTag(String tagId, String name) async {
    await _assertTagNameAvailable(name, excludeTagId: tagId);
    final db = await _db;
    await db.update('tags', {'name': name}, where: 'id = ?', whereArgs: [tagId]);
  }

  Future<void> deleteTag(String tagId) async {
    await deleteTagWithStrategy(tagId: tagId, replacementTagId: null);
  }

  Future<void> deleteTagWithStrategy({
    required String tagId,
    String? replacementTagId,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replacementTagId != null && replacementTagId != tagId) {
        await txn.rawInsert(
          '''
          INSERT OR IGNORE INTO pdf_file_tags (pdf_id, tag_id)
          SELECT pdf_id, ?
          FROM pdf_file_tags
          WHERE tag_id = ?
          ''',
          [replacementTagId, tagId],
        );
        await txn.rawInsert(
          '''
          INSERT OR IGNORE INTO sub_structure_slot_tags (slot_id, tag_id)
          SELECT slot_id, ?
          FROM sub_structure_slot_tags
          WHERE tag_id = ?
          ''',
          [replacementTagId, tagId],
        );
      }
      await txn.delete('tags', where: 'id = ?', whereArgs: [tagId]);
    });
  }

  Future<List<Tag>> getTags() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map((row) => TagMapper.toDomain(TagDto.fromMap(row))).toList();
  }

  Future<Tag?> getTag(String id) async {
    final db = await _db;
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<Map<String, TagUsageStats>> getTagUsageStats() async {
    final db = await _db;
    final pdfUsageRows = await db.rawQuery(
      'SELECT tag_id, COUNT(DISTINCT pdf_id) AS usage_count FROM pdf_file_tags GROUP BY tag_id',
    );
    final slotUsageRows = await db.rawQuery(
      'SELECT tag_id, COUNT(DISTINCT slot_id) AS usage_count FROM sub_structure_slot_tags GROUP BY tag_id',
    );

    final pdfUsage = <String, int>{
      for (final row in pdfUsageRows)
        row['tag_id'] as String: (row['usage_count'] as int?) ?? 0,
    };
    final slotUsage = <String, int>{
      for (final row in slotUsageRows)
        row['tag_id'] as String: (row['usage_count'] as int?) ?? 0,
    };

    final tags = await getTags();
    return {
      for (final tag in tags)
        tag.id: TagUsageStats(
          pdfCount: pdfUsage[tag.id] ?? 0,
          slotCount: slotUsage[tag.id] ?? 0,
        ),
    };
  }

  Future<TagUsageStats> getTagUsage(String tagId) async {
    final usage = await getTagUsageStats();
    return usage[tagId] ?? const TagUsageStats(pdfCount: 0, slotCount: 0);
  }

  String normalizeComparableText(
    String value, {
    bool caseFold = true,
    bool removeDiacritics = true,
  }) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (removeDiacritics) {
      normalized = _stripDiacritics(normalized);
    }
    if (caseFold) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  String normalizeTagName(
    String value, {
    bool caseFold = true,
    bool removeDiacritics = true,
  }) {
    return normalizeComparableText(
      value,
      caseFold: caseFold,
      removeDiacritics: removeDiacritics,
    );
  }

  Future<void> _assertTagNameAvailable(String name, {String? excludeTagId}) async {
    final normalizedCandidate = normalizeComparableText(name);
    final tags = await getTags();
    for (final existing in tags) {
      if (excludeTagId != null && existing.id == excludeTagId) continue;
      if (normalizeComparableText(existing.name) == normalizedCandidate) {
        throw TagNameConflictException('Já existe uma tag equivalente: "${existing.name}".');
      }
    }
  }

  Future<void> _validateTemplate(StructureTemplate template, {String? excludeTemplateId}) async {
    final normalizedName = template.name.trim();
    if (normalizedName.isEmpty) {
      throw const TemplateNameConflictException('Informe um nome de template válido.');
    }

    final candidate = normalizeComparableText(normalizedName);
    final templates = await getTemplates();
    for (final existing in templates) {
      if (excludeTemplateId != null && existing.id == excludeTemplateId) continue;
      if (normalizeComparableText(existing.name) == candidate) {
        throw TemplateNameConflictException('Já existe um template equivalente: "${existing.name}".');
      }
    }

    final usedSlotNames = <String>{};
    for (final slot in template.slots) {
      final slotName = slot.name.trim();
      if (slotName.isEmpty) {
        throw const SlotNameValidationException('Toda sub-estrutura precisa ter um nome válido.');
      }
      final normalizedSlotName = normalizeComparableText(slotName);
      if (!usedSlotNames.add(normalizedSlotName)) {
        throw SlotNameValidationException('Não é permitido nome de sub-estrutura duplicado no mesmo template.');
      }
    }
  }

  String _stripDiacritics(String input) {
    const diacritics = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'ç': 'c',
      'Ç': 'C',
      'ñ': 'n',
      'Ñ': 'N',
    };
    return input.split('').map((char) => diacritics[char] ?? char).join();
  }

  Future<void> addPdf(PdfFile pdf) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('pdf_files', PdfFileMapper.toDto(pdf).toMap());

      for (final tagId in pdf.tagIds.toSet()) {
        await txn.insert(
          'pdf_file_tags',
          {'pdf_id': pdf.id, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> updatePdfTags(String pdfId, List<String> tagIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('pdf_file_tags', where: 'pdf_id = ?', whereArgs: [pdfId]);
      for (final tagId in tagIds.toSet()) {
        await txn.insert(
          'pdf_file_tags',
          {'pdf_id': pdfId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> updatePdfLocation(
    String pdfId,
    String newPath, {
    String? uri,
    String? sourceFolderUri,
    String? sourceDocumentUri,
  }) async {
    final db = await _db;
    await db.update(
      'pdf_files',
      {
        'path': newPath,
        'uri': uri,
        'source_folder_uri': sourceFolderUri,
        'source_document_uri': sourceDocumentUri,
      },
      where: 'id = ?',
      whereArgs: [pdfId],
    );
  }

  Future<List<PdfFile>> getPdfs() async {
    final db = await _db;
    final pdfRows = await db.query('pdf_files', orderBy: 'display_name COLLATE NOCASE ASC');
    final linkRows = await db.query('pdf_file_tags');

    final tagsByPdf = <String, List<String>>{};
    for (final row in linkRows) {
      final pdfId = row['pdf_id'] as String;
      final tagId = row['tag_id'] as String;
      tagsByPdf.putIfAbsent(pdfId, () => []).add(tagId);
    }

    return pdfRows
        .map((row) => PdfFileMapper.toDomain(PdfFileDto.fromMap(row, tagIds: tagsByPdf[row['id'] as String] ?? [])))
        .toList();
  }

  Future<List<PdfFile>> findPdfsByTags(List<String> tagIds) async {
    final pdfs = await getPdfs();
    if (tagIds.isEmpty) return pdfs;
    return pdfs.where((pdf) => tagIds.every(pdf.tagIds.contains)).toList();
  }

  Future<bool> ensureAndroidStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final photosStatus = await Permission.photos.request();
    if (photosStatus.isGranted || photosStatus.isLimited) {
      return true;
    }

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  Future<List<PdfImportCandidate>> scanPdfDirectory(String folderTreeUri) async {
    final documents = await _uriAccessService.listTreeDocumentsRecursively(folderTreeUri);
    final candidates = documents
        .where((doc) => doc.isPdf)
        .map(
          (doc) => PdfImportCandidate(
            sourceId: 'saf://${doc.uri}',
            displayName: doc.displayName,
            uri: doc.uri,
            sourceFolderUri: folderTreeUri,
            sourceDocumentUri: doc.uri,
            size: doc.size,
            mimeType: doc.mimeType,
          ),
        )
        .toList();
    candidates.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return candidates;
  }

  Future<ImportResult> importPdfCandidates({
    required List<PdfImportCandidate> candidates,
    required List<String> tagIds,
    required String idPrefix,
    bool generateHash = true,
    DuplicateImportBehavior onDuplicate = DuplicateImportBehavior.skip,
  }) async {
    final db = await _db;
    var importedCount = 0;
    var updatedCount = 0;
    final errors = <ImportError>[];

    final existingRows = await db.query('pdf_files', columns: ['id', 'path', 'file_hash']);
    final pdfIdByPath = <String, String>{
      for (final row in existingRows) row['path'] as String: row['id'] as String,
    };
    final pdfIdByHash = <String, String>{
      for (final row in existingRows)
        if (row['file_hash'] != null) row['file_hash'] as String: row['id'] as String,
    };
    final tagRows = await db.query('pdf_file_tags', columns: ['pdf_id', 'tag_id']);
    final currentTagIdsByPdf = <String, Set<String>>{};
    for (final row in tagRows) {
      final pdfId = row['pdf_id'] as String;
      final tagId = row['tag_id'] as String;
      currentTagIdsByPdf.putIfAbsent(pdfId, () => <String>{}).add(tagId);
    }

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final source = candidate.path;

      if (!candidate.displayName.toLowerCase().endsWith('.pdf') && !source.toLowerCase().endsWith('.pdf')) {
        errors.add(ImportError(code: 'NOT_PDF', source: source, cause: 'Arquivo não é PDF.'));
        continue;
      }

      final isSafCandidate = candidate.uri != null && candidate.uri!.startsWith('content://');
      final file = File(source);
      if (!isSafCandidate && !await file.exists()) {
        errors.add(ImportError(code: 'INACCESSIBLE', source: source, cause: 'Arquivo inacessível.'));
        continue;
      }

      final duplicateByPathId = pdfIdByPath[source];
      if (duplicateByPathId != null) {
        if (onDuplicate == DuplicateImportBehavior.mergeTags) {
          final existingTags = currentTagIdsByPdf.putIfAbsent(duplicateByPathId, () => <String>{});
          final mergedTags = {...existingTags, ...tagIds};
          if (mergedTags.length > existingTags.length) {
            await updatePdfTags(duplicateByPathId, mergedTags.toList());
            currentTagIdsByPdf[duplicateByPathId] = mergedTags;
            updatedCount++;
          }
        } else {
          errors.add(ImportError(code: 'DUPLICATE_PATH', source: source, cause: 'Arquivo já importado (mesmo caminho).'));
        }
        continue;
      }

      String? hash;
      if (generateHash) {
        try {
          final bytes = isSafCandidate ? await readUriBytes(candidate.uri!) : await file.readAsBytes();
          if (bytes == null) {
            errors.add(ImportError(code: 'URI_ACCESS_FAILED', source: source, cause: 'Falha ao acessar arquivo por URI.'));
            continue;
          }
          hash = sha256.convert(bytes).toString();
        } catch (_) {
          errors.add(ImportError(code: 'HASH_FAILED', source: source, cause: 'Falha ao calcular hash do arquivo.'));
          continue;
        }
      }

      final duplicateByHashId = hash == null ? null : pdfIdByHash[hash];
      if (duplicateByHashId != null) {
        if (onDuplicate == DuplicateImportBehavior.mergeTags) {
          final existingTags = currentTagIdsByPdf.putIfAbsent(duplicateByHashId, () => <String>{});
          final mergedTags = {...existingTags, ...tagIds};
          if (mergedTags.length > existingTags.length) {
            await updatePdfTags(duplicateByHashId, mergedTags.toList());
            currentTagIdsByPdf[duplicateByHashId] = mergedTags;
            updatedCount++;
          }
        } else {
          errors.add(ImportError(code: 'DUPLICATE_HASH', source: source, cause: 'Arquivo duplicado detectado por hash.'));
        }
        continue;
      }

      final title = candidate.displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

      final pdfId = '$idPrefix-$i-${DateTime.now().microsecondsSinceEpoch}';
      await addPdf(
        PdfFile(
          id: pdfId,
          path: source,
          title: title,
          uri: candidate.uri,
          displayName: candidate.displayName,
          fileHash: hash,
          tagIds: tagIds,
          sourceFolderUri: candidate.sourceFolderUri,
          sourceDocumentUri: candidate.sourceDocumentUri,
        ),
      );

      if (candidate.uri != null && candidate.uri!.startsWith('content://')) {
        final permissionGranted = await persistUriPermission(candidate.uri!);
        if (!permissionGranted) {
          errors.add(
            ImportError(
              code: 'URI_PERMISSION_NOT_PERSISTED',
              source: source,
              cause: 'Acesso URI não pôde ser persistido. Relocalize se necessário após reiniciar.',
            ),
          );
        }
      }

      pdfIdByPath[source] = pdfId;
      currentTagIdsByPdf[pdfId] = tagIds.toSet();
      if (hash != null) {
        pdfIdByHash[hash] = pdfId;
      }
      importedCount++;
    }

    return ImportResult(importedCount: importedCount, updatedCount: updatedCount, errors: errors);
  }

  Future<bool> persistUriPermission(String uri) async {
    final db = await _db;
    final grantedAt = DateTime.now().toIso8601String();

    await db.insert(
      'persisted_uri_permissions',
      {
        'uri': uri,
        'granted_at': grantedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (!Platform.isAndroid || !uri.startsWith('content://')) {
      return true;
    }

    final granted = await _uriAccessService.persistReadPermission(uri);
    if (!granted) {
      await db.delete('persisted_uri_permissions', where: 'uri = ?', whereArgs: [uri]);
    }
    return granted;
  }

  Future<Uint8List?> readUriBytes(String uri) async {
    if (!uri.startsWith('content://')) {
      return null;
    }
    return _uriAccessService.readBytes(uri);
  }

  Future<void> addTemplate(StructureTemplate template) async {
    await _validateTemplate(template);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('structure_templates', {
        'id': template.id,
        'name': template.name.trim(),
      });
      await _upsertSlotsForTemplate(txn, template);
    });
  }

  Future<void> updateTemplate(StructureTemplate template) async {
    await _validateTemplate(template, excludeTemplateId: template.id);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('structure_templates', {'name': template.name.trim()}, where: 'id = ?', whereArgs: [template.id]);
      await txn.delete(
        'sub_structure_slot_tags',
        where: 'slot_id IN (SELECT id FROM sub_structure_slots WHERE template_id = ?)',
        whereArgs: [template.id],
      );
      await txn.delete('sub_structure_slots', where: 'template_id = ?', whereArgs: [template.id]);
      await _upsertSlotsForTemplate(txn, template);
    });
  }

  Future<void> deleteTemplate(String templateId) async {
    final db = await _db;
    await db.delete('structure_templates', where: 'id = ?', whereArgs: [templateId]);
  }

  Future<void> _upsertSlotsForTemplate(Transaction txn, StructureTemplate template) async {
    for (var i = 0; i < template.slots.length; i++) {
      final slot = template.slots[i];
      await txn.insert('sub_structure_slots', {
        'id': slot.id,
        'template_id': template.id,
        'name': slot.name.trim(),
        'position': i,
      });

      for (final tagId in slot.requiredTagIds.toSet()) {
        await txn.insert(
          'sub_structure_slot_tags',
          {'slot_id': slot.id, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  Future<List<StructureTemplate>> getTemplates() async {
    final db = await _db;
    final templateRows = await db.query('structure_templates', orderBy: 'name COLLATE NOCASE ASC');
    final slotRows = await db.query('sub_structure_slots', orderBy: 'position ASC');
    final slotTagRows = await db.query('sub_structure_slot_tags');

    final tagIdsBySlot = <String, List<String>>{};
    for (final row in slotTagRows) {
      final slotId = row['slot_id'] as String;
      final tagId = row['tag_id'] as String;
      tagIdsBySlot.putIfAbsent(slotId, () => []).add(tagId);
    }

    final slotsByTemplate = <String, List<SubStructureSlot>>{};
    for (final row in slotRows) {
      final templateId = row['template_id'] as String;
      final slot = SubStructureSlot(
        id: row['id'] as String,
        name: row['name'] as String,
        requiredTagIds: tagIdsBySlot[row['id'] as String] ?? [],
      );
      slotsByTemplate.putIfAbsent(templateId, () => []).add(slot);
    }

    return templateRows
        .map(
          (row) => StructureTemplate(
            id: row['id'] as String,
            name: row['name'] as String,
            slots: slotsByTemplate[row['id'] as String] ?? [],
          ),
        )
        .toList();
  }

  Future<StructureTemplate?> getTemplate(String id) async {
    final templates = await getTemplates();
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  Future<void> addInstance(StructureInstance instance) async {
    final db = await _db;
    await db.insert('structure_instances', {
      'id': instance.id,
      'template_id': instance.templateId,
      'name': instance.name,
      'created_at': instance.createdAt.toIso8601String(),
      'is_completed': instance.isCompleted ? 1 : 0,
      'template_snapshot_json': jsonEncode(instance.templateSnapshot.toMap()),
    });

    for (final entry in instance.selectedPdfIds.entries) {
      await updateInstanceSelection(instance.id, entry.key, entry.value);
    }
  }

  Future<void> updateInstanceMeta({
    required String instanceId,
    String? name,
    bool? isCompleted,
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (name != null) values['name'] = name;
    if (isCompleted != null) values['is_completed'] = isCompleted ? 1 : 0;
    if (values.isEmpty) return;
    await db.update('structure_instances', values, where: 'id = ?', whereArgs: [instanceId]);
  }

  Future<void> renameInstance(String instanceId, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) return;
    await updateInstanceMeta(instanceId: instanceId, name: normalized);
  }

  Future<void> clearAllInstanceSelections(String instanceId) async {
    final db = await _db;
    await db.delete('instance_slot_selection', where: 'instance_id = ?', whereArgs: [instanceId]);
  }

  Future<void> deleteInstance(String instanceId) async {
    final db = await _db;
    await db.delete('structure_instances', where: 'id = ?', whereArgs: [instanceId]);
  }

  Future<StructureInstance?> getInstance(String instanceId) async {
    final db = await _db;
    final rows = await db.query('structure_instances', where: 'id = ?', whereArgs: [instanceId], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final selections = await getInstanceSelections(instanceId);
    final snapshot = StructureTemplate.fromMap(jsonDecode(row['template_snapshot_json'] as String) as Map<String, dynamic>);
    return StructureInstance(
      id: row['id'] as String,
      templateId: row['template_id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      isCompleted: (row['is_completed'] as int? ?? 0) == 1,
      templateSnapshot: snapshot,
      selectedPdfIds: selections,
    );
  }

  Future<List<StructureInstance>> getInstances({DateTime? startDate, DateTime? endDate, String? templateId}) async {
    final db = await _db;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (startDate != null) {
      whereClauses.add('created_at >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClauses.add('created_at <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    if (templateId != null && templateId.isNotEmpty) {
      whereClauses.add('template_id = ?');
      whereArgs.add(templateId);
    }

    final rows = await db.query(
      'structure_instances',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );

    final instances = <StructureInstance>[];
    for (final row in rows) {
      final id = row['id'] as String;
      instances.add(
        StructureInstance(
          id: id,
          templateId: row['template_id'] as String,
          name: row['name'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          isCompleted: (row['is_completed'] as int? ?? 0) == 1,
          templateSnapshot: StructureTemplate.fromMap(
            jsonDecode(row['template_snapshot_json'] as String) as Map<String, dynamic>,
          ),
          selectedPdfIds: await getInstanceSelections(id),
        ),
      );
    }
    return instances;
  }

  Future<StructureInstance> duplicateInstance(StructureInstance source) async {
    final duplicated = StructureInstance(
      id: 'inst-${DateTime.now().microsecondsSinceEpoch}',
      templateId: source.templateId,
      name: '${source.name} (cópia)',
      createdAt: DateTime.now(),
      templateSnapshot: source.templateSnapshot,
      selectedPdfIds: {for (final entry in source.selectedPdfIds.entries) entry.key: List<String>.from(entry.value)},
    );
    await addInstance(duplicated);
    return duplicated;
  }

  Future<void> clearInstanceSelection(String instanceId, String slotId) async {
    final db = await _db;
    await db.delete(
      'instance_slot_selection',
      where: 'instance_id = ? AND slot_id = ?',
      whereArgs: [instanceId, slotId],
    );
  }

  Future<void> updateInstanceSelection(String instanceId, String slotId, List<String> pdfIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'instance_slot_selection',
        where: 'instance_id = ? AND slot_id = ?',
        whereArgs: [instanceId, slotId],
      );

      for (var index = 0; index < pdfIds.length; index++) {
        final pdfId = pdfIds[index];
        await txn.insert('instance_slot_selection', {
          'instance_id': instanceId,
          'slot_id': slotId,
          'pdf_id': pdfId,
          'position': index,
        });
      }
    });
  }

  Future<Map<String, List<String>>> getInstanceSelections(String instanceId) async {
    final db = await _db;
    final rows = await db.query(
      'instance_slot_selection',
      where: 'instance_id = ?',
      whereArgs: [instanceId],
      orderBy: 'slot_id ASC, position ASC',
    );

    final selections = <String, List<String>>{};
    for (final row in rows) {
      final slotId = row['slot_id'] as String;
      final pdfId = row['pdf_id'] as String?;
      if (pdfId == null || pdfId.isEmpty) continue;
      selections.putIfAbsent(slotId, () => <String>[]).add(pdfId);
    }
    return selections;
  }
}
