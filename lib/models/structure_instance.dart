import 'structure_template.dart';

/// Representa uma instância concreta de uma estrutura.
/// Exemplo: "Missa do dia 25/12/2023".
class StructureInstance {
  final String id;
  final String templateId; // Referência ao StructureTemplate
  String name; // Nome desta instância específica
  DateTime createdAt;
  bool isCompleted;

  // Snapshot da estrutura no momento da criação da instância.
  // Política de integridade: instâncias antigas permanecem estáveis mesmo se o template for alterado.
  StructureTemplate templateSnapshot;

  // Mapeia o ID do slot para o ID do PdfFile selecionado
  // Pode ser null se ainda não foi selecionado
  Map<String, String?> selectedPdfIds;

  StructureInstance({
    required this.id,
    required this.templateId,
    required this.name,
    required this.createdAt,
    required this.templateSnapshot,
    this.isCompleted = false,
    Map<String, String?>? selectedPdfIds,
  }) : selectedPdfIds = selectedPdfIds ?? {};
}
