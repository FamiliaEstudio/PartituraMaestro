import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pastoral_pdf_organizer/domain/usecases/build_instance_from_template.dart';
import 'package:pastoral_pdf_organizer/main.dart';
import 'package:pastoral_pdf_organizer/models/structure_instance.dart';
import 'package:pastoral_pdf_organizer/models/structure_template.dart';
import 'package:pastoral_pdf_organizer/services/data_service.dart';

import 'test_db_utils.dart';

void main() {
  final service = DataService();

  setUpAll(configureTestDatabase);

  setUp(() async {
    await resetDatabase();
  });

  Future<void> _pumpStructuresHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataService>.value(value: service),
          Provider<BuildInstanceFromTemplate>(create: (_) => BuildInstanceFromTemplate(service)),
        ],
        child: const MaterialApp(home: StructuresHome()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renomear instância atualiza lista ao voltar', (tester) async {
    final template = StructureTemplate(
      id: 'tpl-rename',
      name: 'Missa',
      slots: [SubStructureSlot(id: 'slot-1', name: 'Entrada')],
    );
    await service.addTemplate(template);
    await service.addInstance(
      StructureInstance(
        id: 'inst-rename',
        templateId: template.id,
        name: 'Instância Original',
        createdAt: DateTime(2026, 1, 1),
        templateSnapshot: template,
      ),
    );

    await _pumpStructuresHome(tester);
    expect(find.text('Instância Original'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações da instância'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Instância Renomeada');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Instância Original'), findsNothing);
    expect(find.text('Instância Renomeada'), findsOneWidget);
  });

  testWidgets('excluir instância remove item da lista imediatamente', (tester) async {
    final template = StructureTemplate(
      id: 'tpl-delete',
      name: 'Celebração',
      slots: [SubStructureSlot(id: 'slot-1', name: 'Glória')],
    );
    await service.addTemplate(template);
    await service.addInstance(
      StructureInstance(
        id: 'inst-delete',
        templateId: template.id,
        name: 'Instância para Excluir',
        createdAt: DateTime(2026, 1, 1),
        templateSnapshot: template,
      ),
    );

    await _pumpStructuresHome(tester);
    expect(find.text('Instância para Excluir'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações da instância'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(find.text('Instância para Excluir'), findsNothing);
  });
}
