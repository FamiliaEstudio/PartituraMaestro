import '../../services/data_service.dart';

class FindCandidatePdfs {
  const FindCandidatePdfs(this._dataService);

  final DataService _dataService;

  Future<List<PdfImportCandidate>> call(String folderPath) {
    return _dataService.scanPdfDirectory(folderPath);
  }
}
