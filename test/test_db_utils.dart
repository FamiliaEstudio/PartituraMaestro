import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> configureTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<void> resetDatabase() async {
  final dbPath = await getDatabasesPath();
  final path = p.join(dbPath, 'partitura_maestro.db');
  await deleteDatabase(path);
}
