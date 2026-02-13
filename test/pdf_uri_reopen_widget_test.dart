import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pastoral_pdf_organizer/models/pdf_file.dart';
import 'package:pastoral_pdf_organizer/screens/pdf_viewer_screen.dart';
import 'package:pastoral_pdf_organizer/services/data_service.dart';
import 'package:provider/provider.dart';

import 'test_db_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('partituramaestro/uri_access');
  const uri = 'content://com.example.documents/partitura.pdf';
  final pdfBytes = Uint8List.fromList(
    '%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF'.codeUnits,
  );

  setUpAll(configureTestDatabase);

  setUp(() async {
    await resetDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openUriBytes') {
        if ((call.arguments as Map)['uri'] == uri) {
          return pdfBytes;
        }
      }
      if (call.method == 'persistUriPermission') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('mostra ação de relocalização quando arquivo local está ausente', (tester) async {
    final service = DataService();
    await service.addPdf(
      PdfFile(
        id: 'missing-local',
        path: '/tmp/inexistente.pdf',
        title: 'inexistente',
        displayName: 'inexistente.pdf',
        tagIds: const [],
      ),
    );

    final missingPdf = (await service.getPdfs()).single;

    await tester.pumpWidget(
      Provider<DataService>.value(
        value: service,
        child: MaterialApp(home: PdfViewerScreen(pdfFile: missingPdf)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Arquivo ausente ou movido. Relocalize para continuar.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Relocalizar arquivo'), findsOneWidget);
  });

  testWidgets('abre PDF via fallback de URI após reinício simulado do app', (tester) async {
    final service = DataService();
    final tempDir = await Directory.systemTemp.createTemp('pdf-uri-fallback');
    final localPath = p.join(tempDir.path, 'partitura.pdf');
    final localFile = File(localPath);
    await localFile.writeAsBytes(pdfBytes);

    await service.importPdfCandidates(
      candidates: [
        PdfImportCandidate(
          sourceId: localPath,
          displayName: 'partitura.pdf',
          uri: uri,
        ),
      ],
      tagIds: [],
      idPrefix: 'uri-reopen',
      generateHash: false,
    );

    final imported = await service.getPdfs();
    expect(imported, hasLength(1));

    await localFile.delete();
    await tempDir.delete();

    final restartedService = DataService();
    final reopenedPdf = (await restartedService.getPdfs()).single;

    await tester.pumpWidget(
      Provider<DataService>.value(
        value: restartedService,
        child: MaterialApp(home: PdfViewerScreen(pdfFile: reopenedPdf)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Relocalize para continuar'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
