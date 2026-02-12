import '../../models/structure_template.dart';
import '../../services/data_service.dart';

class CreateTemplate {
  const CreateTemplate(this._dataService);

  final DataService _dataService;

  Future<void> call(StructureTemplate template) {
    return _dataService.addTemplate(template);
  }
}
