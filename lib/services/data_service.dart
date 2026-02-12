import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../models/tag.dart';

class DataService {
  final List<Tag> _tags = [];
  final List<PdfFile> _pdfs = [];
  final List<StructureTemplate> _templates = [];
  final List<StructureInstance> _instances = [];

  static final DataService _instance = DataService._internal();

  factory DataService() => _instance;

  DataService._internal();

  void addTag(Tag tag) {
    final exists = _tags.any(
      (t) => t.name.toLowerCase().trim() == tag.name.toLowerCase().trim(),
    );
    if (!exists) {
      _tags.add(tag);
    }
  }

  List<Tag> getTags() => List.unmodifiable(_tags);

  Tag? getTag(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  void addPdf(PdfFile pdf) {
    _pdfs.add(pdf);
  }

  List<PdfFile> getPdfs() => List.unmodifiable(_pdfs);

  void addTagToPdf(String pdfId, String tagId) {
    final pdf = _pdfs.firstWhere((p) => p.id == pdfId);
    if (!pdf.tagIds.contains(tagId)) {
      pdf.tagIds.add(tagId);
    }
  }

  List<PdfFile> findPdfsByTags(List<String> tagIds) {
    if (tagIds.isEmpty) {
      return getPdfs();
    }

    return _pdfs
        .where((pdf) => tagIds.every((tId) => pdf.tagIds.contains(tId)))
        .toList();
  }

  void addTemplate(StructureTemplate template) {
    _templates.add(template);
  }

  List<StructureTemplate> getTemplates() => List.unmodifiable(_templates);

  StructureTemplate? getTemplate(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  void addInstance(StructureInstance instance) {
    _instances.add(instance);
  }

  void updateInstanceSelection(String instanceId, String slotId, String pdfId) {
    final instance = _instances.firstWhere((i) => i.id == instanceId);
    instance.selectedPdfIds[slotId] = pdfId;
  }
}
