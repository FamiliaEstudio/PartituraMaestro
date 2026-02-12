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
    List<String>? requiredTagIds,
  }) : requiredTagIds = requiredTagIds ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'requiredTagIds': requiredTagIds,
    };
  }

  factory SubStructureSlot.fromMap(Map<String, dynamic> map) {
    return SubStructureSlot(
      id: map['id'] as String,
      name: map['name'] as String,
      requiredTagIds: List<String>.from(map['requiredTagIds'] as List? ?? const []),
    );
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
    List<SubStructureSlot>? slots,
  }) : slots = slots ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slots': slots.map((s) => s.toMap()).toList(),
    };
  }

  factory StructureTemplate.fromMap(Map<String, dynamic> map) {
    return StructureTemplate(
      id: map['id'] as String,
      name: map['name'] as String,
      slots: (map['slots'] as List? ?? const [])
          .map((slot) => SubStructureSlot.fromMap(Map<String, dynamic>.from(slot as Map)))
          .toList(),
    );
  }
}
