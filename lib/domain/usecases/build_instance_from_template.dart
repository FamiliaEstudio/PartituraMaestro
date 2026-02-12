import 'package:uuid/uuid.dart';

import '../../models/structure_instance.dart';
import '../../models/structure_template.dart';
import '../../services/data_service.dart';

class BuildInstanceFromTemplate {
  const BuildInstanceFromTemplate(this._dataService);

  final DataService _dataService;

  Future<StructureInstance> call(StructureTemplate template) async {
    final instance = StructureInstance(
      id: const Uuid().v4(),
      templateId: template.id,
      name: '${template.name} - ${DateTime.now().toString().split(' ')[0]}',
      createdAt: DateTime.now(),
      templateSnapshot: template,
    );
    await _dataService.addInstance(instance);
    return instance;
  }
}
