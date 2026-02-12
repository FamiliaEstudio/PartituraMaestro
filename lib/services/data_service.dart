import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import 'storage/database_service.dart';

class ImportError {
  final String source;
  final String reason;

  const ImportError({required this.source, required this.reason});
}

class ImportResult {
  final int importedCount;
  final List<ImportError> errors;

  const ImportResult({required this.importedCount, required this.errors});
}

class PdfImportCandidate {
  final String path;
  final String displayName;
  final String? uri;

  const PdfImportCandidate({
    required this.path,
    required this.displayName,
    this.uri,
  });
}

class DataService {
  static final DataService _instance = DataService._internal();

  factory DataService() => _instance;

  DataService._internal();

  final DatabaseService _databaseService = DatabaseService();
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
    final db = await _db;
    await db.insert(
      'tags',
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateTag(String tagId, String name) async {
    final db = await _db;
    await db.update('tags', {'name': name}, where: 'id = ?', whereArgs: [tagId]);
  }

  Future<void> deleteTag(String tagId) async {
    final db = await _db;
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  Future<List<Tag>> getTags() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Tag.fromMap).toList();
  }

  Future<Tag?> getTag(String id) async {
    final db = await _db;
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<void> addPdf(PdfFile pdf) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('pdf_files', {
        'id': pdf.id,
        'path': pdf.path,
        'title': pdf.title,
        'uri': pdf.uri,
        'display_name': pdf.displayName,
        'file_hash': pdf.fileHash,
      });

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

  Future<void> updatePdfLocation(String pdfId, String newPath, {String? uri}) async {
    final db = await _db;
    await db.update(
      'pdf_files',
      {
        'path': newPath,
        'uri': uri,
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
        .map(
          (row) => PdfFile(
            id: row['id'] as String,
            path: row['path'] as String,
            title: row['title'] as String,
            uri: row['uri'] as String?,
            displayName: (row['display_name'] as String?) ?? (row['title'] as String),
            fileHash: row['file_hash'] as String?,
            tagIds: tagsByPdf[row['id'] as String] ?? [],
          ),
        )
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

  Future<List<PdfImportCandidate>> scanPdfDirectory(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw FileSystemException('Pasta não encontrada', folderPath);
    }

    final entities = await dir.list(recursive: true, followLinks: false).toList();
    final candidates = <PdfImportCandidate>[];
    for (final entity in entities) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.pdf')) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : entity.path.split(Platform.pathSeparator).last;
      candidates.add(PdfImportCandidate(path: entity.path, displayName: name));
    }
    candidates.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return candidates;
  }

  Future<ImportResult> importPdfCandidates({
    required List<PdfImportCandidate> candidates,
    required List<String> tagIds,
    required String idPrefix,
    bool generateHash = true,
  }) async {
    final db = await _db;
    var importedCount = 0;
    final errors = <ImportError>[];

    final existingRows = await db.query('pdf_files', columns: ['path', 'file_hash']);
    final existingPaths = existingRows.map((row) => row['path'] as String).toSet();
    final existingHashes = existingRows
        .map((row) => row['file_hash'] as String?)
        .whereType<String>()
        .toSet();

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final source = candidate.path;

      if (!candidate.displayName.toLowerCase().endsWith('.pdf') && !source.toLowerCase().endsWith('.pdf')) {
        errors.add(ImportError(source: source, reason: 'Arquivo não é PDF.'));
        continue;
      }

      final file = File(source);
      if (!await file.exists()) {
        errors.add(ImportError(source: source, reason: 'Arquivo inacessível.'));
        continue;
      }

      if (existingPaths.contains(source)) {
        errors.add(ImportError(source: source, reason: 'Arquivo já importado (mesmo caminho).'));
        continue;
      }

      String? hash;
      if (generateHash) {
        try {
          final bytes = await file.readAsBytes();
          hash = sha256.convert(bytes).toString();
        } catch (_) {
          errors.add(ImportError(source: source, reason: 'Falha ao calcular hash do arquivo.'));
          continue;
        }
      }

      if (hash != null && existingHashes.contains(hash)) {
        errors.add(ImportError(source: source, reason: 'Arquivo duplicado detectado por hash.'));
        continue;
      }

      final title = candidate.displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

      await addPdf(
        PdfFile(
          id: '$idPrefix-$i-${DateTime.now().microsecondsSinceEpoch}',
          path: source,
          title: title,
          uri: candidate.uri,
          displayName: candidate.displayName,
          fileHash: hash,
          tagIds: tagIds,
        ),
      );

      if (candidate.uri != null && candidate.uri!.startsWith('content://')) {
        await persistUriPermission(candidate.uri!);
      }

      existingPaths.add(source);
      if (hash != null) {
        existingHashes.add(hash);
      }
      importedCount++;
    }

    return ImportResult(importedCount: importedCount, errors: errors);
  }

  Future<void> persistUriPermission(String uri) async {
    final db = await _db;
    await db.insert(
      'persisted_uri_permissions',
      {
        'uri': uri,
        'granted_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addTemplate(StructureTemplate template) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('structure_templates', {
        'id': template.id,
        'name': template.name,
      });
      await _upsertSlotsForTemplate(txn, template);
    });
  }

  Future<void> updateTemplate(StructureTemplate template) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('structure_templates', {'name': template.name}, where: 'id = ?', whereArgs: [template.id]);
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
        'name': slot.name,
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
      if (entry.value == null) continue;
      await updateInstanceSelection(instance.id, entry.key, entry.value!);
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
      selectedPdfIds: Map<String, String?>.from(source.selectedPdfIds),
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

  Future<void> updateInstanceSelection(String instanceId, String slotId, String pdfId) async {
    final db = await _db;
    await db.insert(
      'instance_slot_selection',
      {'instance_id': instanceId, 'slot_id': slotId, 'pdf_id': pdfId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String?>> getInstanceSelections(String instanceId) async {
    final db = await _db;
    final rows = await db.query(
      'instance_slot_selection',
      where: 'instance_id = ?',
      whereArgs: [instanceId],
    );

    return {
      for (final row in rows)
        row['slot_id'] as String: row['pdf_id'] as String?,
    };
  }
}
