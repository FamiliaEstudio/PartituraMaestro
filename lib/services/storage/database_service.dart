import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static const _databaseName = 'partitura_maestro.db';
  static const _databaseVersion = 4;

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      );
    ''');

    await db.execute('''
      CREATE TABLE pdf_files (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        title TEXT NOT NULL,
        uri TEXT,
        source_folder_uri TEXT,
        source_document_uri TEXT,
        display_name TEXT NOT NULL,
        file_hash TEXT
      );
    ''');

    await db.execute('CREATE UNIQUE INDEX idx_pdf_file_hash ON pdf_files(file_hash) WHERE file_hash IS NOT NULL;');
    await db.execute('CREATE UNIQUE INDEX idx_pdf_path ON pdf_files(path);');

    await db.execute('''
      CREATE TABLE persisted_uri_permissions (
        uri TEXT PRIMARY KEY,
        granted_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE pdf_file_tags (
        pdf_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (pdf_id, tag_id),
        FOREIGN KEY (pdf_id) REFERENCES pdf_files(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE structure_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE sub_structure_slots (
        id TEXT PRIMARY KEY,
        template_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        FOREIGN KEY (template_id) REFERENCES structure_templates(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE sub_structure_slot_tags (
        slot_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (slot_id, tag_id),
        FOREIGN KEY (slot_id) REFERENCES sub_structure_slots(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE structure_instances (
        id TEXT PRIMARY KEY,
        template_id TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        template_snapshot_json TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE instance_slot_selection (
        instance_id TEXT NOT NULL,
        slot_id TEXT NOT NULL,
        pdf_id TEXT,
        PRIMARY KEY (instance_id, slot_id),
        FOREIGN KEY (instance_id) REFERENCES structure_instances(id) ON DELETE CASCADE,
        FOREIGN KEY (pdf_id) REFERENCES pdf_files(id) ON DELETE SET NULL
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE pdf_files ADD COLUMN uri TEXT;');
      await db.execute('ALTER TABLE pdf_files ADD COLUMN display_name TEXT;');
      await db.execute('ALTER TABLE pdf_files ADD COLUMN file_hash TEXT;');
      await db.execute('UPDATE pdf_files SET display_name = title WHERE display_name IS NULL;');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_pdf_file_hash ON pdf_files(file_hash) WHERE file_hash IS NOT NULL;');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_pdf_path ON pdf_files(path);');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS persisted_uri_permissions (
          uri TEXT PRIMARY KEY,
          granted_at TEXT NOT NULL
        );
      ''');
    }

    if (oldVersion < 3) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE structure_instances RENAME TO structure_instances_old;');
        await txn.execute('''
          CREATE TABLE structure_instances (
            id TEXT PRIMARY KEY,
            template_id TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            template_snapshot_json TEXT NOT NULL
          );
        ''');

        final templates = await txn.query('structure_templates');
        final slots = await txn.query('sub_structure_slots', orderBy: 'position ASC');
        final slotTags = await txn.query('sub_structure_slot_tags');

        final slotTagMap = <String, List<String>>{};
        for (final row in slotTags) {
          final slotId = row['slot_id'] as String;
          final tagId = row['tag_id'] as String;
          slotTagMap.putIfAbsent(slotId, () => []).add(tagId);
        }

        final slotsByTemplate = <String, List<Map<String, dynamic>>>{};
        for (final row in slots) {
          final templateId = row['template_id'] as String;
          slotsByTemplate.putIfAbsent(templateId, () => []).add({
            'id': row['id'] as String,
            'name': row['name'] as String,
            'requiredTagIds': slotTagMap[row['id'] as String] ?? <String>[],
          });
        }

        final snapshotByTemplate = <String, String>{};
        for (final row in templates) {
          final id = row['id'] as String;
          final name = row['name'] as String;
          final slotsForTemplate = slotsByTemplate[id] ?? <Map<String, dynamic>>[];
          snapshotByTemplate[id] = jsonEncode({'id': id, 'name': name, 'slots': slotsForTemplate});
        }

        final oldInstances = await txn.query('structure_instances_old');
        for (final row in oldInstances) {
          final templateId = row['template_id'] as String;
          final snapshot = snapshotByTemplate[templateId] ?? jsonEncode({'id': templateId, 'name': 'Template removido', 'slots': []});
          await txn.insert('structure_instances', {
            'id': row['id'],
            'template_id': templateId,
            'name': row['name'],
            'created_at': row['created_at'],
            'is_completed': 0,
            'template_snapshot_json': snapshot,
          });
        }

        await txn.execute('DROP TABLE structure_instances_old;');

        await txn.execute('ALTER TABLE instance_slot_selection RENAME TO instance_slot_selection_old;');
        await txn.execute('''
          CREATE TABLE instance_slot_selection (
            instance_id TEXT NOT NULL,
            slot_id TEXT NOT NULL,
            pdf_id TEXT,
            PRIMARY KEY (instance_id, slot_id),
            FOREIGN KEY (instance_id) REFERENCES structure_instances(id) ON DELETE CASCADE,
            FOREIGN KEY (pdf_id) REFERENCES pdf_files(id) ON DELETE SET NULL
          );
        ''');
        await txn.execute('''
          INSERT INTO instance_slot_selection (instance_id, slot_id, pdf_id)
          SELECT instance_id, slot_id, pdf_id
          FROM instance_slot_selection_old;
        ''');
        await txn.execute('DROP TABLE instance_slot_selection_old;');
      });
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE pdf_files ADD COLUMN source_folder_uri TEXT;');
      await db.execute('ALTER TABLE pdf_files ADD COLUMN source_document_uri TEXT;');
    }

  }
}
