class Tag {
  final String id;
  String name;
  // Pode ter cor ou ícone futuramente

  Tag({required this.id, required this.name});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'],
      name: map['name'],
    );
  }
}
