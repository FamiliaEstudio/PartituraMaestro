/// Define um "slot" ou "sub-estrutura" dentro de uma estrutura maior.
/// Exemplo: "Entrada" dentro da estrutura "Missa".
/// Este slot define quais tags são aceitas ou preferidas para filtrar os PDFs.
class SubStructureSlot {
  final String id;
  String name;
  List<String> requiredTagIds; // Tags que o PDF DEVE ter

  // Poderíamos ter tags opcionais ou banidas também

  SubStructureSlot({
    required this.id,
    required this.name,
    this.requiredTagIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'requiredTagIds': requiredTagIds,
    };
  }
}

/// Define o modelo da estrutura criada pelo usuário.
/// Exemplo: "Missa", "Reunião de Diretoria", "Aula".
class StructureTemplate {
  final String id;
  String name;
  List<SubStructureSlot> slots;

  StructureTemplate({
    required this.id,
    required this.name,
    this.slots = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slots': slots.map((s) => s.toMap()).toList(),
    };
  }
}
