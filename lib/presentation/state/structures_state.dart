import 'package:flutter/foundation.dart';

import '../../models/structure_instance.dart';
import '../../models/structure_template.dart';
import '../../services/data_service.dart';

class StructuresState extends ChangeNotifier {
  StructuresState(this._dataService);

  final DataService _dataService;

  List<StructureTemplate> templates = [];
  List<StructureInstance> instances = [];
  String? templateFilterId;
  DateTime? startDate;
  DateTime? endDate;
  bool isLoading = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();

    templates = await _dataService.getTemplates();
    instances = await _dataService.getInstances(
      templateId: templateFilterId,
      startDate: startDate,
      endDate: endDate,
    );

    isLoading = false;
    notifyListeners();
  }

  Future<void> setTemplateFilter(String? value) async {
    templateFilterId = value;
    await load();
  }

  Future<void> setStartDate(DateTime? value) async {
    startDate = value;
    await load();
  }

  Future<void> setEndDate(DateTime? value) async {
    endDate = value;
    await load();
  }

  Future<void> clearFilters() async {
    templateFilterId = null;
    startDate = null;
    endDate = null;
    await load();
  }
}
