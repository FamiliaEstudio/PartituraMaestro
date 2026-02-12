import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pastoral_pdf_organizer/models/pdf_file.dart';
import 'package:pastoral_pdf_organizer/models/structure_instance.dart';
import 'package:pastoral_pdf_organizer/models/structure_template.dart';
import 'package:pastoral_pdf_organizer/models/tag.dart';
import 'package:pastoral_pdf_organizer/domain/usecases/create_template.dart';
import 'package:pastoral_pdf_organizer/screens/create_template_screen.dart';
import 'package:pastoral_pdf_organizer/screens/import_pdf_screen.dart';
import 'package:pastoral_pdf_organizer/screens/instance_selection_screen.dart';
import 'package:pastoral_pdf_organizer/screens/tag_management_screen.dart';
import 'package:pastoral_pdf_organizer/services/data_service.dart';

import 'test_db_utils.dart';

void main() {
  final service = DataService();

  setUpAll(configureTestDatabase);

  setUp(() async {
    await resetDatabase();
  });

  testWidgets('fluxo de criar tag adiciona item na lista', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TagManagementScreen(onDataChanged: () {})),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ofertório');
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('Ofertório'), findsOneWidget);
  });

  testWidgets('fluxo de importação valida seleção mínima de PDFs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ImportPdfScreen(onImported: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar na biblioteca'));
    await tester.pump();

    expect(find.text('Selecione ao menos um arquivo PDF.'), findsOneWidget);
  });

  testWidgets('fluxo de criar template salva sub-estrutura', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateTemplateScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Missa');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar Sub-estrutura'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Entrada');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar Estrutura'));
    await tester.pumpAndSettle();

    final templates = await service.getTemplates();
    expect(templates, hasLength(1));
    expect(templates.first.slots.map((e) => e.name), ['Entrada']);
  });



  testWidgets('formulário de template exibe erro para nome de template duplicado', (tester) async {
    await service.addTemplate(
      StructureTemplate(
        id: 'tpl-existing',
        name: 'Missa Solene',
        slots: [SubStructureSlot(id: 'slot-existing', name: 'Entrada')],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataService>.value(value: service),
          Provider<CreateTemplate>(create: (_) => CreateTemplate(service)),
        ],
        child: const MaterialApp(home: CreateTemplateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'míssa solene');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar Sub-estrutura'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ato Penitencial');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar Estrutura'));
    await tester.pump();

    expect(find.text('Já existe um template equivalente: "Missa Solene".'), findsOneWidget);
  });

  testWidgets('formulário de template exibe erro ao salvar sub-estrutura sem nome', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataService>.value(value: service),
          Provider<CreateTemplate>(create: (_) => CreateTemplate(service)),
        ],
        child: const MaterialApp(home: CreateTemplateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Missa');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar Sub-estrutura'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
    await tester.pump();

    expect(find.text('Toda sub-estrutura precisa ter um nome válido.'), findsOneWidget);
  });

  testWidgets('seleção de slot lista apenas PDFs com todas tags exigidas', (tester) async {
    await service.addTag(Tag(id: 'tag-entrada', name: 'Entrada'));
    await service.addTag(Tag(id: 'tag-natal', name: 'Natal'));

    await service.addPdf(
      PdfFile(
        id: 'pdf-ok',
        path: '/tmp/entrada-natal.pdf',
        title: 'Entrada Natal',
        tagIds: ['tag-entrada', 'tag-natal'],
      ),
    );
    await service.addPdf(
      PdfFile(
        id: 'pdf-incompleto',
        path: '/tmp/entrada-comum.pdf',
        title: 'Entrada Comum',
        tagIds: ['tag-entrada'],
      ),
    );

    final template = StructureTemplate(
      id: 'tpl-tags',
      name: 'Missa',
      slots: [
        SubStructureSlot(
          id: 'slot-entrada-natal',
          name: 'Entrada',
          requiredTagIds: ['tag-entrada', 'tag-natal'],
        ),
      ],
    );
    await service.addTemplate(template);

    final instance = StructureInstance(
      id: 'inst-tags',
      templateId: template.id,
      name: 'Missa de Natal',
      createdAt: DateTime(2026, 12, 24),
      templateSnapshot: template,
    );
    await service.addInstance(instance);

    await tester.pumpWidget(MaterialApp(home: InstanceSelectionScreen(instance: instance)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrada'));
    await tester.pumpAndSettle();

    expect(find.text('Entrada Natal'), findsOneWidget);
    expect(find.text('Entrada Comum'), findsNothing);
  });

  testWidgets('fluxo de montar instância permite selecionar PDF por slot', (tester) async {
    await service.addTag(Tag(id: 'tag-1', name: 'Entrada'));
    await service.addPdf(
      PdfFile(
        id: 'pdf-1',
        path: '/tmp/entrada.pdf',
        title: 'Entrada Solene',
        tagIds: ['tag-1'],
      ),
    );

    final template = StructureTemplate(
      id: 'tpl-1',
      name: 'Missa',
      slots: [SubStructureSlot(id: 'slot-1', name: 'Entrada', requiredTagIds: ['tag-1'])],
    );
    await service.addTemplate(template);

    final instance = StructureInstance(
      id: 'inst-1',
      templateId: template.id,
      name: 'Missa Dominical',
      createdAt: DateTime(2026, 1, 1),
      templateSnapshot: template,
    );
    await service.addInstance(instance);

    await tester.pumpWidget(
      MaterialApp(home: InstanceSelectionScreen(instance: instance)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrada'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrada Solene'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selecionado: Entrada Solene'), findsOneWidget);
  });
}
