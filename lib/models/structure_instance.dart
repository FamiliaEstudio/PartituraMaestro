/// Representa uma instância concreta de uma estrutura.
/// Exemplo: "Missa do dia 25/12/2023".
class StructureInstance {
  final String id;
  final String templateId; // Referência ao StructureTemplate
  String name; // Nome desta instância específica
  DateTime createdAt;

  // Mapeia o ID do slot para o ID do PdfFile selecionado
  // Pode ser null se ainda não foi selecionado
  Map<String, String?> selectedPdfIds;

  StructureInstance({
    required this.id,
    required this.templateId,
    required this.name,
    required this.createdAt,
    Map<String, String?>? selectedPdfIds,
  }) : selectedPdfIds = selectedPdfIds ?? {};
}
