import '../models/tag.dart';
import '../models/pdf_file.dart';
import '../models/structure_template.dart';
import '../models/structure_instance.dart';

// Mock data service para simular persistência
class DataService {
  // Simulating database
  final List<Tag> _tags = [];
  final List<PdfFile> _pdfs = [];
  final List<StructureTemplate> _templates = [];
  final List<StructureInstance> _instances = [];

  // Singleton pattern
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // --- Tags ---
  void addTag(Tag tag) {
    _tags.add(tag);
  }

  List<Tag> getTags() => List.unmodifiable(_tags);

  Tag? getTag(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  // --- PDFs ---
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

  // Encontrar PDFs que correspondam às tags
  List<PdfFile> findPdfsByTags(List<String> tagIds) {
    if (tagIds.isEmpty) return getPdfs();

    return _pdfs.where((pdf) {
      // Verifica se o PDF possui TODAS as tags requeridas (AND logic)
      // Ou poderia ser ANY (OR logic), dependendo do requisito.
      // O usuário pediu "possuem as tag's específicas", assumirei que
      // se a sub-estrutura pede Tag A e Tag B, o PDF deve ter ambas?
      // Ou talvez o sub-slot define um conjunto de tags possíveis?
      // O requisito diz: "separa dentro da estrutura sub-estruturas que aceitam determinadas tag's"
      // Geralmente "Missa" -> "Entrada". Entrada aceita PDFs com tag "Entrada".
      // Se tiver tag "Natal" e "Entrada", filtra por ambas.

      return tagIds.every((tId) => pdf.tagIds.contains(tId));
    }).toList();
  }

  // --- Templates ---
  void addTemplate(StructureTemplate template) {
    _templates.add(template);
  }

  List<StructureTemplate> getTemplates() => List.unmodifiable(_templates);

  StructureTemplate? getTemplate(String id) {
     try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  // --- Instances ---
  void addInstance(StructureInstance instance) {
    _instances.add(instance);
  }

  void updateInstanceSelection(String instanceId, String slotId, String pdfId) {
    final instance = _instances.firstWhere((i) => i.id == instanceId);
    instance.selectedPdfIds[slotId] = pdfId;
  }
}
