import 'package:sqflite/sqflite.dart';

import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';
import 'storage/database_service.dart';

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
        tagIds: ['t1', 't2'],
      ),
    );
    await addPdf(
      PdfFile(
        id: 'p2',
        path: '/docs/canto2.pdf',
        title: 'Glória Solene',
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

  Future<List<PdfFile>> getPdfs() async {
    final db = await _db;
    final pdfRows = await db.query('pdf_files', orderBy: 'title COLLATE NOCASE ASC');
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

  Future<void> addTemplate(StructureTemplate template) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('structure_templates', {
        'id': template.id,
        'name': template.name,
      });

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
    });
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
    });
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
