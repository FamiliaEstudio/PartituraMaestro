import 'package:flutter_test/flutter_test.dart';

import 'package:pastoral_pdf_organizer/models/pdf_file.dart';
import 'package:pastoral_pdf_organizer/models/structure_instance.dart';
import 'package:pastoral_pdf_organizer/models/structure_template.dart';
import 'package:pastoral_pdf_organizer/models/tag.dart';
import 'package:pastoral_pdf_organizer/services/data_service.dart';

import 'test_db_utils.dart';

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
    final entradaNatal = await service.findPdfsByTags(['tag-entrada', 'tag-natal']);
    final semResultado = await service.findPdfsByTags(['tag-gloria', 'tag-natal']);

    expect(onlyEntrada.map((e) => e.id), containsAll(['pdf-1', 'pdf-2']));
    expect(entradaNatal.map((e) => e.id), ['pdf-1']);
    expect(semResultado, isEmpty);
  });

  test('persistência de seleção por slot mantém vínculo com instância', () async {
    await service.addTag(Tag(id: 'tag-entrada', name: 'Entrada'));
    final template = StructureTemplate(
      id: 'tpl-1',
      name: 'Missa',
      slots: [
        SubStructureSlot(id: 'slot-entrada', name: 'Entrada', requiredTagIds: ['tag-entrada']),
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

    await service.updateInstanceSelection('inst-1', 'slot-entrada', 'pdf-entrada');

    final selections = await service.getInstanceSelections('inst-1');
    expect(selections['slot-entrada'], 'pdf-entrada');

    await service.clearInstanceSelection('inst-1', 'slot-entrada');
    final cleared = await service.getInstanceSelections('inst-1');
    expect(cleared.containsKey('slot-entrada'), isFalse);
  });
}
