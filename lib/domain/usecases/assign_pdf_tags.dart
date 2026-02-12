import '../../services/data_service.dart';

class AssignPdfTags {
  const AssignPdfTags(this._dataService);

  final DataService _dataService;

  Future<void> call({required String pdfId, required List<String> tagIds}) {
    return _dataService.updatePdfTags(pdfId, tagIds);
  }
}
